import logging
import traceback
from pathlib import Path
from uuid import uuid4

from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from jinja2 import Environment, FileSystemLoader

from app.config import settings
from app.database import get_analysis, init_database, list_analyses, save_analysis
from app.services.analyzer import Analyzer
from app.services.exports import create_excel, create_pdf

log = logging.getLogger(__name__)

app = FastAPI(title=settings.app_name)

# Jinja2 with cache disabled — workaround for Python 3.14 weakref hash change
_env = Environment(loader=FileSystemLoader(str(settings.base_dir / "app" / "templates")), cache_size=0)
templates = Jinja2Templates(env=_env)

app.mount("/static", StaticFiles(directory=str(settings.base_dir / "app" / "static")), name="static")

analyzer = Analyzer()


@app.on_event("startup")
def startup():
    settings.storage_dir.mkdir(parents=True, exist_ok=True)
    app.mount("/media", StaticFiles(directory=str(settings.storage_dir)), name="media")
    init_database()


@app.get("/", response_class=HTMLResponse)
def index(request: Request):
    return templates.TemplateResponse(request, "index.html", {"app_name": settings.app_name})


@app.get("/api/health")
def health():
    return {"status": "ok"}


@app.post("/api/analyze")
async def analyze(
    file: UploadFile = File(...),
    stop_line_mode: str = Form("auto"),
    x1: float | None = Form(None),
    y1: float | None = Form(None),
    x2: float | None = Form(None),
    y2: float | None = Form(None),
    traffic_light_state: str = Form("auto"),
):
    if stop_line_mode not in {"auto", "auto_fallback", "manual"}:
        raise HTTPException(400, "Неизвестный режим стоп-линии")
    if traffic_light_state not in {"auto", "red", "yellow", "green"}:
        raise HTTPException(400, "Неизвестный режим сигнала")

    suffix = Path(file.filename or "upload.bin").suffix.lower()
    upload_path = settings.upload_dir / f"{uuid4().hex}{suffix}"
    size = 0
    try:
        with upload_path.open("wb") as f:
            while chunk := await file.read(1024 * 1024):
                size += len(chunk)
                if size > settings.max_upload_mb * 1024 * 1024:
                    raise HTTPException(413, f"Максимальный размер файла: {settings.max_upload_mb} МБ")
                f.write(chunk)

        media_type = _media_type(suffix)
        manual = None
        if stop_line_mode == "manual":
            if any(v is None for v in (x1, y1, x2, y2)):
                raise HTTPException(400, "Укажите две точки стоп-линии")
            manual = (float(x1), float(y1), float(x2), float(y2))

        if media_type == "image":
            record = analyzer.analyze_image(upload_path, file.filename or upload_path.name, stop_line_mode, manual, traffic_light_state)
        else:
            record = analyzer.analyze_video(upload_path, file.filename or upload_path.name, stop_line_mode, manual, traffic_light_state)

        save_analysis(record)
        return _public(record)
    except HTTPException:
        raise
    except Exception as e:
        log.error("analyze error:\n%s", traceback.format_exc())
        raise HTTPException(500, str(e)) from e


@app.get("/api/history")
def history(limit: int = 100):
    return [_public(r) for r in list_analyses(min(max(limit, 1), 500))]


@app.get("/api/history/{aid}")
def history_item(aid: str):
    r = get_analysis(aid)
    if not r:
        raise HTTPException(404, "Запись не найдена")
    return _public(r)


@app.get("/api/history/{aid}/report.pdf")
def pdf_report(aid: str):
    r = get_analysis(aid)
    if not r:
        raise HTTPException(404)
    out = settings.result_dir / f"{aid}_report.pdf"
    create_pdf(r, out)
    return FileResponse(out, filename=f"analysis_{aid}.pdf")


@app.get("/api/history/{aid}/report.xlsx")
def excel_report(aid: str):
    r = get_analysis(aid)
    if not r:
        raise HTTPException(404)
    out = settings.result_dir / f"{aid}_report.xlsx"
    create_excel(r, out)
    return FileResponse(out, filename=f"analysis_{aid}.xlsx")


def _media_type(suffix: str) -> str:
    if suffix in {".jpg", ".jpeg", ".png", ".bmp", ".webp"}:
        return "image"
    if suffix in {".mp4", ".avi", ".mov", ".mkv", ".webm", ".m4v"}:
        return "video"
    raise ValueError("Поддерживаются JPG, PNG, WEBP, MP4, AVI, MOV, MKV, WEBM")


def _public(r: dict) -> dict:
    out = dict(r)
    out["result_url"] = f"/media/{r['result_path']}" if r.get("result_path") else None
    out["evidence_url"] = f"/media/{r['evidence_path']}" if r.get("evidence_path") else None
    out["pdf_url"] = f"/api/history/{r['id']}/report.pdf"
    out["excel_url"] = f"/api/history/{r['id']}/report.xlsx"
    return out
