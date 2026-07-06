from datetime import datetime, timezone
from pathlib import Path
from time import perf_counter
from uuid import uuid4

import cv2
import numpy as np

from app.config import settings
from app.services.detector import Detection, VEHICLE_CLASS_IDS, YoloDetector
from app.services.stop_line import (
    Line, StopLineResult,
    detect_stop_line, fallback_stop_line, manual_stop_line,
    line_intersects, below_line,
)
from app.services.tracker import SimpleTracker
from app.services.traffic_light import StateSmoother, detect_signal


STATE_LABELS = {"red": "красный", "yellow": "жёлтый", "green": "зелёный", "unknown": "не определён"}


def _imwrite(path: Path, frame: np.ndarray) -> None:
    ext = path.suffix or ".jpg"
    ok, buf = cv2.imencode(ext, frame)
    if ok:
        path.write_bytes(buf.tobytes())


def _imread(path: Path) -> np.ndarray:
    buf = np.frombuffer(path.read_bytes(), dtype=np.uint8)
    img = cv2.imdecode(buf, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("Не удалось прочитать изображение")
    return img


class Analyzer:
    def __init__(self):
        self._detector = YoloDetector(settings.model_path, settings.confidence, settings.iou_threshold)

    def _pick_line(self, frame, mode, manual_vals) -> StopLineResult:
        if mode == "manual" and manual_vals:
            return manual_stop_line(frame, *manual_vals)
        result = detect_stop_line(frame)
        if result.line is not None:
            return result
        # Always fall back when auto-detection fails — night/dark frames have no edges
        return fallback_stop_line(frame, settings.default_stop_line_y)

    def _draw(self, frame, detections, flagged_ids, stop_line, state):
        if stop_line is not None:
            cv2.line(frame, (int(stop_line.x1), int(stop_line.y1)), (int(stop_line.x2), int(stop_line.y2)), (0, 220, 255), 4)
            cv2.putText(frame, "STOP LINE", (int(stop_line.x1) + 8, max(28, int(stop_line.y1) - 12)), cv2.FONT_HERSHEY_SIMPLEX, 0.75, (0, 220, 255), 2)
        color_map = {"red": (0, 0, 255), "yellow": (0, 200, 255), "green": (0, 210, 0), "unknown": (180, 180, 180)}
        cv2.putText(frame, f"SIGNAL: {state.upper()}", (20, 38), cv2.FONT_HERSHEY_SIMPLEX, 0.9, color_map.get(state, (200, 200, 200)), 2)
        for det in detections:
            if det.class_id not in VEHICLE_CLASS_IDS:
                continue
            x1, y1, x2, y2 = (int(v) for v in det.box)
            flagged = det.track_id in flagged_ids if det.track_id else False
            color = (0, 0, 255) if flagged else (0, 210, 0)
            cv2.rectangle(frame, (x1, y1), (x2, y2), color, 3)
            label = f"{det.label} {det.confidence:.2f}"
            if det.track_id:
                label += f" ID{det.track_id}"
            if flagged:
                label += " VIOLATION"
            cv2.putText(frame, label, (x1, max(22, y1 - 8)), cv2.FONT_HERSHEY_SIMPLEX, 0.55, color, 2)

    # ── IMAGE ──────────────────────────────────────────────────────────
    def analyze_image(self, path: Path, source_name: str, mode: str, manual_vals, override: str) -> dict:
        started = perf_counter()
        aid = uuid4().hex
        frame = _imread(path)
        all_detections = self._detector.predict(frame)
        state = override if override in {"red", "yellow", "green"} else detect_signal(frame, all_detections)
        vehicles = [d for d in all_detections if d.class_id in VEHICLE_CLASS_IDS]
        line_result = self._pick_line(frame, mode, manual_vals)
        possible = []
        evidence_dir = settings.evidence_dir / aid
        flagged_ids: set[int] = set()
        if state == "red" and line_result.line is not None:
            for det in vehicles:
                cx = (det.box[0] + det.box[2]) / 2
                cy = (det.box[1] + det.box[3]) / 2
                # ref_y=0: intersection is toward top of frame; violations are above the stop line
                if below_line(cx, cy, line_result.line, ref_y=0):
                    ev_num = len(possible) + 1
                    evidence_dir.mkdir(parents=True, exist_ok=True)
                    ev_path = evidence_dir / f"event_{ev_num:03d}.jpg"
                    ev_frame = frame.copy()
                    self._draw(ev_frame, [det], {det.track_id} if det.track_id else set(), line_result.line, state)
                    _imwrite(ev_path, ev_frame)
                    if det.track_id:
                        flagged_ids.add(det.track_id)
                    possible.append({
                        "event_number": ev_num,
                        "vehicle_class": det.label,
                        "confidence": det.confidence,
                        "box": list(det.box),
                        "traffic_light_state": state,
                        "evidence_path": str(ev_path.relative_to(settings.storage_dir)),
                    })
        self._draw(frame, all_detections, flagged_ids, line_result.line, state)
        result_path = settings.result_dir / f"{aid}.jpg"
        _imwrite(result_path, frame)
        return {
            "id": aid, "created_at": datetime.now(timezone.utc).isoformat(),
            "source_name": source_name, "media_type": "image", "status": "completed",
            "traffic_light_state": state, "stop_line_mode": line_result.source,
            "stop_line": _line_dict(line_result),
            "detected_vehicles": len(vehicles), "violations": len(possible),
            "processing_seconds": round(perf_counter() - started, 3),
            "result_path": str(result_path.relative_to(settings.storage_dir)),
            "evidence_path": str(evidence_dir.relative_to(settings.storage_dir)) if possible else None,
            "details": {
                "events": possible,
                "traffic_light_label": STATE_LABELS.get(state, state),
            },
        }

    # ── VIDEO ──────────────────────────────────────────────────────────
    def analyze_video(self, path: Path, source_name: str, mode: str, manual_vals, override: str) -> dict:
        started = perf_counter()
        aid = uuid4().hex
        cap = self._open_cap(path)
        fps = cap.get(cv2.CAP_PROP_FPS) or 25.0
        w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        ok, first = cap.read()
        if not ok:
            cap.release()
            raise ValueError("Видео не содержит кадров")
        line_result = self._pick_line(first, mode, manual_vals)
        cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
        result_path = settings.result_dir / f"{aid}.mp4"
        writer, tmp_path = self._open_writer(result_path, fps, w, h)
        tracker = SimpleTracker()
        smoother = StateSmoother(settings.traffic_light_smoothing)
        prev_pos: dict[int, tuple[float, float]] = {}
        counted: set[int] = set()
        events = []
        evidence_dir = settings.evidence_dir / aid
        evidence_dir.mkdir(parents=True, exist_ok=True)
        frame_idx = 0
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            all_det = self._detector.predict(frame)
            raw_state = override if override in {"red", "yellow", "green"} else detect_signal(frame, all_det)
            state = smoother.update(raw_state)
            vehicles_raw = [d for d in all_det if d.class_id in VEHICLE_CLASS_IDS]
            tracked = tracker.update(vehicles_raw)
            flagged_ids: set[int] = set()
            for det in tracked:
                tid = det.track_id
                if tid is None:
                    continue
                cx = (det.box[0] + det.box[2]) / 2
                cy = (det.box[1] + det.box[3]) / 2
                if tid not in counted and state == "red" and line_result.line is not None:
                    prev = prev_pos.get(tid)
                    if prev and line_intersects(prev[0], prev[1], cx, cy, line_result.line):
                        counted.add(tid)
                        flagged_ids.add(tid)
                        ev_path = evidence_dir / f"event_{len(events)+1:03d}.jpg"
                        ev_frame = frame.copy()
                        self._draw(ev_frame, [det], {tid}, line_result.line, state)
                        _imwrite(ev_path, ev_frame)
                        events.append({
                            "event_number": len(events) + 1,
                            "track_id": tid,
                            "vehicle_class": det.label,
                            "confidence": det.confidence,
                            "frame": frame_idx,
                            "time_seconds": round(frame_idx / fps, 2),
                            "traffic_light_state": state,
                            "evidence_path": str(ev_path.relative_to(settings.storage_dir)),
                        })
                if tid in counted:
                    flagged_ids.add(tid)
                prev_pos[tid] = (cx, cy)
            cv2.putText(frame, f"VIOLATIONS: {len(events)}", (20, 75), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 0, 255), 2)
            self._draw(frame, tracked, flagged_ids, line_result.line, state)
            writer.write(frame)
            frame_idx += 1
        cap.release()
        writer.release()
        if tmp_path != result_path:
            import shutil
            shutil.move(str(tmp_path), str(result_path))
        return {
            "id": aid, "created_at": datetime.now(timezone.utc).isoformat(),
            "source_name": source_name, "media_type": "video", "status": "completed",
            "traffic_light_state": smoother.update("unknown"),
            "stop_line_mode": line_result.source,
            "stop_line": _line_dict(line_result),
            "detected_vehicles": len(set(d.track_id for d in tracked if d.track_id)),
            "violations": len(events),
            "processing_seconds": round(perf_counter() - started, 3),
            "result_path": str(result_path.relative_to(settings.storage_dir)),
            "evidence_path": str((evidence_dir).relative_to(settings.storage_dir)) if events else None,
            "details": {
                "events": events, "fps": fps,
                "frames_processed": frame_idx, "source_frames": total_frames,
                "duration_seconds": round(frame_idx / fps, 2),
                "traffic_light_label": STATE_LABELS.get(smoother.update("unknown"), ""),
            },
        }

    def _open_cap(self, path: Path) -> cv2.VideoCapture:
        try:
            str(path).encode("ascii")
            return cv2.VideoCapture(str(path))
        except UnicodeEncodeError:
            import shutil, tempfile
            tmp = Path(tempfile.mktemp(suffix=path.suffix))
            shutil.copy2(path, tmp)
            cap = cv2.VideoCapture(str(tmp))
            try:
                tmp.unlink()
            except Exception:
                pass
            return cap

    def _open_writer(self, path: Path, fps, w, h):
        try:
            str(path).encode("ascii")
            return cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*"mp4v"), fps, (w, h)), path
        except UnicodeEncodeError:
            import tempfile
            tmp = Path(tempfile.mktemp(suffix=path.suffix))
            return cv2.VideoWriter(str(tmp), cv2.VideoWriter_fourcc(*"mp4v"), fps, (w, h)), tmp


def _line_dict(result: StopLineResult) -> dict | None:
    if result.line is None:
        return None
    ln = result.line
    return {"x1": float(ln.x1), "y1": float(ln.y1), "x2": float(ln.x2), "y2": float(ln.y2), "source": result.source}
