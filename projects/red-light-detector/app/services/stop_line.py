from dataclasses import dataclass
import cv2
import numpy as np


@dataclass(frozen=True)
class Line:
    x1: float; y1: float; x2: float; y2: float


@dataclass
class StopLineResult:
    line: Line | None
    source: str
    confidence: float = 0.0


def detect_stop_line(frame: np.ndarray) -> StopLineResult:
    h, w = frame.shape[:2]
    roi_top = int(h * 0.4)
    roi = frame[roi_top:, :]
    gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(blurred, 50, 150)
    lines = cv2.HoughLinesP(edges, 1, np.pi / 180, threshold=80, minLineLength=w * 0.25, maxLineGap=30)
    if lines is None:
        return StopLineResult(None, "none")
    best, best_score = None, 0.0
    for line in lines:
        x1, y1, x2, y2 = line[0]
        dx, dy = abs(x2 - x1), abs(y2 - y1)
        if dx < 10:
            continue
        angle = abs(np.degrees(np.arctan2(dy, dx)))
        if angle > 20:
            continue
        length = np.hypot(dx, dy)
        score = length * (1 - angle / 20)
        if score > best_score:
            best_score = score
            best = (x1, y1 + roi_top, x2, y2 + roi_top)
    if best is None:
        return StopLineResult(None, "none")
    return StopLineResult(Line(*best), "auto", min(best_score / (w * 2), 1.0))


def fallback_stop_line(frame: np.ndarray, y_frac: float = 0.65) -> StopLineResult:
    h, w = frame.shape[:2]
    y = int(h * y_frac)
    return StopLineResult(Line(0, y, w, y), "fallback", 0.3)


def manual_stop_line(frame: np.ndarray, x1f: float, y1f: float, x2f: float, y2f: float) -> StopLineResult:
    h, w = frame.shape[:2]
    return StopLineResult(Line(x1f * w, y1f * h, x2f * w, y2f * h), "manual", 1.0)


def line_intersects(px: float, py: float, qx: float, qy: float, line: Line) -> bool:
    """True if segment PQ crosses the stop line."""
    def cross(ax, ay, bx, by, cx, cy):
        return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
    d1 = cross(line.x1, line.y1, line.x2, line.y2, px, py)
    d2 = cross(line.x1, line.y1, line.x2, line.y2, qx, qy)
    d3 = cross(px, py, qx, qy, line.x1, line.y1)
    d4 = cross(px, py, qx, qy, line.x2, line.y2)
    return (d1 * d2 < 0) and (d3 * d4 < 0)


def below_line(x: float, y: float, line: Line, ref_y: float) -> bool:
    """True if point (x,y) is on the same side as ref_y relative to the line."""
    dx = line.x2 - line.x1
    dy = line.y2 - line.y1
    if abs(dx) < 1e-6:
        return False
    line_y = line.y1 + dy * (x - line.x1) / dx
    return (y - line_y) * (ref_y - line_y) > 0
