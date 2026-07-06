from pathlib import Path
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_name: str = "Детекция проезда на красный сигнал"
    base_dir: Path = Path(__file__).parent.parent
    model_path: Path = Path(__file__).parent.parent / "models" / "yolov8n.onnx"
    storage_dir: Path = Path(__file__).parent.parent / "storage"
    confidence: float = 0.35
    iou_threshold: float = 0.45
    max_upload_mb: int = 500
    default_stop_line_y: float = 0.65
    traffic_light_smoothing: int = 5

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8", "extra": "ignore"}

    @property
    def upload_dir(self) -> Path:
        p = self.storage_dir / "uploads"
        p.mkdir(parents=True, exist_ok=True)
        return p

    @property
    def result_dir(self) -> Path:
        p = self.storage_dir / "results"
        p.mkdir(parents=True, exist_ok=True)
        return p

    @property
    def evidence_dir(self) -> Path:
        p = self.storage_dir / "evidence"
        p.mkdir(parents=True, exist_ok=True)
        return p

    @property
    def db_path(self) -> Path:
        self.storage_dir.mkdir(parents=True, exist_ok=True)
        return self.storage_dir / "history.sqlite3"


settings = Settings()
