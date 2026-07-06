"""YOLOv8 inference via ONNX Runtime — no PyTorch required."""
from dataclasses import dataclass
from pathlib import Path
from threading import Lock

import numpy as np
import onnxruntime as ort


VEHICLE_CLASS_IDS = {2, 3, 5, 7}   # car, motorcycle, bus, truck
TRAFFIC_LIGHT_CLASS_ID = 9
INPUT_SIZE = 640


@dataclass(frozen=True)
class Detection:
    box: tuple[float, float, float, float]   # x1 y1 x2 y2 (pixel coords)
    confidence: float
    class_id: int
    label: str
    track_id: int | None = None


class YoloDetector:
    _LABELS = [
        "person","bicycle","car","motorcycle","airplane","bus","train","truck","boat",
        "traffic light","fire hydrant","stop sign","parking meter","bench","bird","cat",
        "dog","horse","sheep","cow","elephant","bear","zebra","giraffe","backpack",
        "umbrella","handbag","tie","suitcase","frisbee","skis","snowboard","sports ball",
        "kite","baseball bat","baseball glove","skateboard","surfboard","tennis racket",
        "bottle","wine glass","cup","fork","knife","spoon","bowl","banana","apple",
        "sandwich","orange","broccoli","carrot","hot dog","pizza","donut","cake","chair",
        "couch","potted plant","bed","dining table","toilet","tv","laptop","mouse",
        "remote","keyboard","cell phone","microwave","oven","toaster","sink","refrigerator",
        "book","clock","vase","scissors","teddy bear","hair drier","toothbrush",
    ]

    def __init__(self, model_path: Path, conf: float = 0.35, iou: float = 0.45):
        opts = ort.SessionOptions()
        opts.inter_op_num_threads = 1
        opts.intra_op_num_threads = 4
        self._session = ort.InferenceSession(
            str(model_path),
            sess_options=opts,
            providers=["CPUExecutionProvider"],
        )
        self._input_name = self._session.get_inputs()[0].name
        self._conf = conf
        self._iou = iou
        self._lock = Lock()

    # ------------------------------------------------------------------
    def predict(self, frame: np.ndarray, classes: set[int] | None = None) -> list[Detection]:
        blob, scale, pad = self._preprocess(frame)
        with self._lock:
            raw = self._session.run(None, {self._input_name: blob})[0]
        return self._postprocess(raw, scale, pad, frame.shape, classes)

    # ------------------------------------------------------------------
    def _preprocess(self, frame: np.ndarray):
        h, w = frame.shape[:2]
        scale = INPUT_SIZE / max(h, w)
        nh, nw = int(h * scale), int(w * scale)
        import cv2
        resized = cv2.resize(frame, (nw, nh))
        pad_h, pad_w = INPUT_SIZE - nh, INPUT_SIZE - nw
        padded = np.full((INPUT_SIZE, INPUT_SIZE, 3), 114, dtype=np.uint8)
        padded[:nh, :nw] = resized
        blob = padded[:, :, ::-1].astype(np.float32) / 255.0   # BGR→RGB, norm
        blob = np.ascontiguousarray(blob.transpose(2, 0, 1)[None])  # BCHW
        return blob, scale, (pad_h, pad_w)

    def _postprocess(self, raw, scale, pad, orig_shape, classes):
        # raw: (1, 84, 8400) — cx cy w h + 80 class scores
        pred = raw[0].T   # (8400, 84)
        boxes_cxcywh = pred[:, :4]
        scores = pred[:, 4:]
        class_ids = scores.argmax(axis=1)
        confidences = scores[np.arange(len(scores)), class_ids]

        mask = confidences >= self._conf
        if classes:
            mask &= np.isin(class_ids, list(classes))
        boxes_cxcywh = boxes_cxcywh[mask]
        confidences = confidences[mask]
        class_ids = class_ids[mask]

        if len(boxes_cxcywh) == 0:
            return []

        # Convert cx cy w h → x1 y1 x2 y2 (in padded 640x640 space)
        x1 = boxes_cxcywh[:, 0] - boxes_cxcywh[:, 2] / 2
        y1 = boxes_cxcywh[:, 1] - boxes_cxcywh[:, 3] / 2
        x2 = boxes_cxcywh[:, 0] + boxes_cxcywh[:, 2] / 2
        y2 = boxes_cxcywh[:, 1] + boxes_cxcywh[:, 3] / 2

        # Map back to original image coords
        ph, pw = pad
        x1 = (x1 - 0) / scale
        y1 = (y1 - 0) / scale
        x2 = (x2 - 0) / scale
        y2 = (y2 - 0) / scale

        oh, ow = orig_shape[:2]
        x1 = np.clip(x1, 0, ow)
        y1 = np.clip(y1, 0, oh)
        x2 = np.clip(x2, 0, ow)
        y2 = np.clip(y2, 0, oh)

        # NMS
        keep = self._nms(np.stack([x1, y1, x2, y2], axis=1), confidences)
        result = []
        for i in keep:
            result.append(Detection(
                box=(float(x1[i]), float(y1[i]), float(x2[i]), float(y2[i])),
                confidence=float(confidences[i]),
                class_id=int(class_ids[i]),
                label=self._LABELS[int(class_ids[i])] if int(class_ids[i]) < len(self._LABELS) else str(class_ids[i]),
            ))
        return result

    def _nms(self, boxes, scores):
        x1, y1, x2, y2 = boxes[:, 0], boxes[:, 1], boxes[:, 2], boxes[:, 3]
        areas = (x2 - x1) * (y2 - y1)
        order = scores.argsort()[::-1]
        keep = []
        while order.size > 0:
            i = order[0]
            keep.append(i)
            ix1 = np.maximum(x1[i], x1[order[1:]])
            iy1 = np.maximum(y1[i], y1[order[1:]])
            ix2 = np.minimum(x2[i], x2[order[1:]])
            iy2 = np.minimum(y2[i], y2[order[1:]])
            inter = np.maximum(0, ix2 - ix1) * np.maximum(0, iy2 - iy1)
            iou = inter / (areas[i] + areas[order[1:]] - inter + 1e-6)
            order = order[1:][iou <= self._iou]
        return keep
