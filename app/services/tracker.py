"""Simple IoU-based multi-object tracker — no external dependencies."""
from dataclasses import dataclass, field

import numpy as np


@dataclass
class Track:
    track_id: int
    box: tuple[float, float, float, float]
    class_id: int
    label: str
    confidence: float
    age: int = 0
    missed: int = 0


class SimpleTracker:
    def __init__(self, iou_threshold: float = 0.3, max_missed: int = 10):
        self._iou_threshold = iou_threshold
        self._max_missed = max_missed
        self._tracks: list[Track] = []
        self._next_id = 1

    def update(self, detections) -> list:
        """Return detections enriched with track_id."""
        if not self._tracks:
            for det in detections:
                self._tracks.append(Track(self._next_id, det.box, det.class_id, det.label, det.confidence))
                self._next_id += 1
            result = [_with_id(det, t.track_id) for det, t in zip(detections, self._tracks)]
            return result

        if not detections:
            for t in self._tracks:
                t.missed += 1
            self._tracks = [t for t in self._tracks if t.missed <= self._max_missed]
            return []

        track_boxes = np.array([t.box for t in self._tracks])
        det_boxes = np.array([d.box for d in detections])
        iou_matrix = _iou_matrix(track_boxes, det_boxes)

        matched_tracks = set()
        matched_dets = set()
        assigned: dict[int, int] = {}   # det_idx → track_idx

        for _ in range(min(len(self._tracks), len(detections))):
            if iou_matrix.size == 0:
                break
            idx = int(np.argmax(iou_matrix))
            ti, di = divmod(idx, iou_matrix.shape[1])
            if iou_matrix[ti, di] < self._iou_threshold:
                break
            assigned[di] = ti
            matched_tracks.add(ti)
            matched_dets.add(di)
            iou_matrix[ti, :] = -1
            iou_matrix[:, di] = -1

        for ti, t in enumerate(self._tracks):
            if ti not in matched_tracks:
                t.missed += 1
            else:
                t.missed = 0
                t.age += 1

        result = []
        for di, det in enumerate(detections):
            if di in assigned:
                ti = assigned[di]
                t = self._tracks[ti]
                t.box = det.box
                t.confidence = det.confidence
                result.append(_with_id(det, t.track_id))
            else:
                new_track = Track(self._next_id, det.box, det.class_id, det.label, det.confidence)
                self._tracks.append(new_track)
                result.append(_with_id(det, self._next_id))
                self._next_id += 1

        self._tracks = [t for t in self._tracks if t.missed <= self._max_missed]
        return result

    def reset(self):
        self._tracks.clear()
        self._next_id = 1


def _with_id(det, track_id: int):
    from app.services.detector import Detection
    return Detection(det.box, det.confidence, det.class_id, det.label, track_id)


def _iou_matrix(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    ax1, ay1, ax2, ay2 = a[:, 0], a[:, 1], a[:, 2], a[:, 3]
    bx1, by1, bx2, by2 = b[:, 0], b[:, 1], b[:, 2], b[:, 3]
    inter_x1 = np.maximum(ax1[:, None], bx1[None, :])
    inter_y1 = np.maximum(ay1[:, None], by1[None, :])
    inter_x2 = np.minimum(ax2[:, None], bx2[None, :])
    inter_y2 = np.minimum(ay2[:, None], by2[None, :])
    inter = np.maximum(0, inter_x2 - inter_x1) * np.maximum(0, inter_y2 - inter_y1)
    area_a = (ax2 - ax1) * (ay2 - ay1)
    area_b = (bx2 - bx1) * (by2 - by1)
    return inter / (area_a[:, None] + area_b[None, :] - inter + 1e-6)
