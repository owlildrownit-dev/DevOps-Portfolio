import logging
import multiprocessing
import socket
import threading
import time
from urllib.error import URLError
from urllib.request import urlopen

import uvicorn
import webview

from app.config import settings
from app.main import app


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _wait(url: str, timeout: float = 60.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with urlopen(f"{url}/api/health", timeout=2):
                return
        except (URLError, OSError):
            time.sleep(0.2)
    raise RuntimeError("Сервер не запустился")


def main() -> int:
    log_path = settings.storage_dir / "app.log"
    settings.storage_dir.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(
        filename=str(log_path), level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s", encoding="utf-8",
    )
    port = _free_port()
    url = f"http://127.0.0.1:{port}"
    cfg = uvicorn.Config(app, host="127.0.0.1", port=port, log_level="warning", access_log=False)
    server = uvicorn.Server(cfg)
    thread = threading.Thread(target=server.run, daemon=True, name="api")
    try:
        thread.start()
        _wait(url)
        webview.create_window(
            settings.app_name, url,
            width=1440, height=900, min_size=(1024, 700),
            resizable=True, confirm_close=True, background_color="#0f1725",
        )
        webview.start(debug=False)
        return 0
    except Exception:
        logging.exception("Ошибка запуска")
        return 1
    finally:
        server.should_exit = True
        thread.join(timeout=5)


if __name__ == "__main__":
    multiprocessing.freeze_support()
    raise SystemExit(main())
