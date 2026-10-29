import logging
from collections import deque
import cv2
import numpy as np
from app.services.detector import Detection, TRAFFIC_LIGHT_CLASS_ID

log = logging.getLogger(__name__)


def detect_signal(frame: np.ndarray, detections: list[Detection]) -> str:
    tl_boxes = [d.box for d in detections if d.class_id == TRAFFIC_LIGHT_CLASS_ID]
    log.debug("traffic_light detections: %d boxes", len(tl_boxes))

    if tl_boxes:
        for box in tl_boxes:
            x1, y1, x2, y2 = (int(v) for v in box)
            crop = frame[y1:y2, x1:x2]
            state = _hsv_crop(crop)
            log.debug("crop (%d,%d)-(%d,%d) → %s", x1, y1, x2, y2, state)
            if state != "unknown":
                return state

    # Fallback: scan upper 60 % of frame, no positional weighting
    h = frame.shape[0]
    region = frame[:int(h * 0.6), :]
    state = _hsv_region(region)
    log.debug("full-frame fallback → %s", state)
    return state


# ── crop logic: use thirds (red top, yellow mid, green bot) ──────────────────
def _hsv_crop(img: np.ndarray) -> str:
    if img.size == 0:
        return "unknown"
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    h, w = hsv.shape[:2]
    t = max(h // 3, 1)

    red    = _px(hsv[:t],     [0,80,60],[15,255,255], [155,80,60],[180,255,255])
    yellow = _px(hsv[t:2*t],  [15,80,60],[38,255,255])
    green  = _px(hsv[2*t:],   [38,60,40],[95,255,255])
    log.debug("crop thirds  r=%d y=%d g=%d (thresh=%.1f)", red, yellow, green, max(t*w*0.02, 4))

    thr = max(t * w * 0.02, 4)
    return _pick({"red": red, "yellow": yellow, "green": green}, thr)


# ── fallback: entire region, no positional constraint ────────────────────────
def _hsv_region(img: np.ndarray) -> str:
    if img.size == 0:
        return "unknown"
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)

    red    = _px(hsv, [0,100,80],[15,255,255], [155,100,80],[180,255,255])
    yellow = _px(hsv, [15,150,120],[38,255,255])   # high S+V: street lamps are S<120
    green  = _px(hsv, [38,80,60],[95,255,255])
    log.debug("region scan  r=%d y=%d g=%d (thresh=5)", red, yellow, green)

    return _pick({"red": red, "yellow": yellow, "green": green}, thr=5)


def _px(region, lo, hi, lo2=None, hi2=None) -> int:
    m = cv2.inRange(region, np.array(lo, np.uint8), np.array(hi, np.uint8))
    if lo2 is not None:
        m |= cv2.inRange(region, np.array(lo2, np.uint8), np.array(hi2, np.uint8))
    return int(m.sum() // 255)


def _pick(scores: dict, thr: float) -> str:
    best, val = max(scores.items(), key=lambda x: x[1])
    return best if val >= thr else "unknown"


class StateSmoother:
    def __init__(self, window: int = 5):
        self._buf: deque[str] = deque(maxlen=window)

    def update(self, state: str) -> str:
        self._buf.append(state)
        counts = {}
        for s in self._buf:
            counts[s] = counts.get(s, 0) + 1
        return max(counts, key=counts.get)
