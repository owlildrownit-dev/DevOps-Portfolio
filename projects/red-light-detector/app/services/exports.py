from pathlib import Path
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import cm
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle, Image as RLImage
from reportlab.lib import colors
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment

# Register Cyrillic-capable font from Windows system fonts
_FONT_REGISTERED = False

def _register_fonts():
    global _FONT_REGISTERED
    if _FONT_REGISTERED:
        return
    candidates = [
        ("C:/Windows/Fonts/arial.ttf",   "C:/Windows/Fonts/arialbd.ttf"),
        ("C:/Windows/Fonts/times.ttf",   "C:/Windows/Fonts/timesbd.ttf"),
        ("C:/Windows/Fonts/calibri.ttf", "C:/Windows/Fonts/calibrib.ttf"),
    ]
    for reg, bold in candidates:
        if Path(reg).exists():
            pdfmetrics.registerFont(TTFont("CyrFont",     reg))
            if Path(bold).exists():
                pdfmetrics.registerFont(TTFont("CyrFont-Bold", bold))
            else:
                pdfmetrics.registerFont(TTFont("CyrFont-Bold", reg))
            _FONT_REGISTERED = True
            return
    # Fallback: Helvetica (no Cyrillic, but won't crash)
    _FONT_REGISTERED = True


def _styles():
    _register_fonts()
    base = getSampleStyleSheet()
    normal = ParagraphStyle("CyrNormal", fontName="CyrFont",      fontSize=10, leading=14)
    title  = ParagraphStyle("CyrTitle",  fontName="CyrFont-Bold", fontSize=14, leading=18, spaceAfter=6)
    h2     = ParagraphStyle("CyrH2",     fontName="CyrFont-Bold", fontSize=11, leading=14, spaceBefore=8, spaceAfter=4)
    return normal, title, h2


def create_pdf(record: dict, output: Path) -> None:
    _register_fonts()
    normal, title_style, h2_style = _styles()

    doc = SimpleDocTemplate(
        str(output), pagesize=A4,
        leftMargin=2*cm, rightMargin=2*cm, topMargin=2*cm, bottomMargin=2*cm,
    )
    story = []

    story.append(Paragraph("Отчёт о детекции проезда на красный сигнал", title_style))
    story.append(Spacer(1, 0.4*cm))

    signal_labels = {"red": "красный", "yellow": "жёлтый", "green": "зелёный", "unknown": "не определён"}

    meta = [
        ["Файл",                record.get("source_name", "—")],
        ["Дата анализа",        record.get("created_at", "—")[:19].replace("T", " ")],
        ["Тип медиа",           "Фото" if record.get("media_type") == "image" else "Видео"],
        ["Сигнал светофора",    signal_labels.get(record.get("traffic_light_state", ""), record.get("traffic_light_state", "—"))],
        ["Обнаружено ТС",       str(record.get("detected_vehicles", 0))],
        ["Нарушений",           str(record.get("violations", 0))],
        ["Время обработки",     f"{record.get('processing_seconds', 0):.1f} с"],
    ]
    t = Table(
        [[Paragraph(k, normal), Paragraph(str(v), normal)] for k, v in meta],
        colWidths=[5*cm, 12*cm],
    )
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (0, -1), colors.HexColor("#E8EDF5")),
        ("FONTNAME",   (0, 0), (-1, -1), "CyrFont"),
        ("FONTSIZE",   (0, 0), (-1, -1), 10),
        ("GRID",       (0, 0), (-1, -1), 0.5, colors.grey),
        ("VALIGN",     (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING",    (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ]))
    story.append(t)

    events = record.get("details", {}).get("events", [])
    storage_dir = Path(__file__).parent.parent.parent / "storage"

    if events:
        story.append(Spacer(1, 0.5*cm))
        story.append(Paragraph("События", h2_style))

        header = ["№", "ТС", "Уверенность", "Время (с)", "Сигнал"]
        rows = [[Paragraph(h, normal) for h in header]]
        for i, e in enumerate(events):
            rows.append([
                Paragraph(str(e.get("event_number", i + 1)), normal),
                Paragraph(e.get("vehicle_class", "—"), normal),
                Paragraph(f"{e.get('confidence', 0):.2f}", normal),
                Paragraph(str(e.get("time_seconds", "—")), normal),
                Paragraph(signal_labels.get(e.get("traffic_light_state", ""), e.get("traffic_light_state", "—")), normal),
            ])

        et = Table(rows, colWidths=[1*cm, 3.5*cm, 3*cm, 3*cm, 3.5*cm])
        et.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#1A3A6B")),
            ("TEXTCOLOR",  (0, 0), (-1, 0), colors.white),
            ("FONTNAME",   (0, 0), (-1, -1), "CyrFont"),
            ("FONTSIZE",   (0, 0), (-1, -1), 9),
            ("GRID",       (0, 0), (-1, -1), 0.5, colors.grey),
            ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F5F8FF")]),
        ]))
        story.append(et)

        # Evidence frames
        has_images = False
        for e in events:
            ev_path_rel = e.get("evidence_path")
            if not ev_path_rel:
                continue
            ev_path = storage_dir / ev_path_rel
            if not ev_path.exists():
                continue
            if not has_images:
                story.append(Spacer(1, 0.5*cm))
                story.append(Paragraph("Скриншоты нарушений", h2_style))
                has_images = True
            story.append(Spacer(1, 0.3*cm))
            story.append(Paragraph(f"Событие {e.get('event_number', '')} — {e.get('vehicle_class', '')} — {e.get('time_seconds', '')} с", normal))
            story.append(Spacer(1, 0.15*cm))
            img = RLImage(str(ev_path), width=15*cm, height=8.4*cm, kind="proportional")
            story.append(img)

    doc.build(story)


def create_excel(record: dict, output: Path) -> None:
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Анализ"
    header_fill = PatternFill(fill_type="solid", fgColor="1A3A6B")
    header_font = Font(bold=True, color="FFFFFF")
    meta_fill   = PatternFill(fill_type="solid", fgColor="E8EDF5")

    signal_labels = {"red": "красный", "yellow": "жёлтый", "green": "зелёный", "unknown": "не определён"}

    rows = [
        ("Файл",         record.get("source_name", "")),
        ("Дата",         record.get("created_at", "")[:19].replace("T", " ")),
        ("Тип",          "Фото" if record.get("media_type") == "image" else "Видео"),
        ("Сигнал",       signal_labels.get(record.get("traffic_light_state", ""), record.get("traffic_light_state", ""))),
        ("ТС",           record.get("detected_vehicles", 0)),
        ("Нарушений",    record.get("violations", 0)),
        ("Время (с)",    record.get("processing_seconds", 0)),
    ]
    for i, (k, v) in enumerate(rows, 1):
        ws.cell(i, 1, k).fill = meta_fill
        ws.cell(i, 2, v)
    ws.column_dimensions["A"].width = 22
    ws.column_dimensions["B"].width = 40

    events = record.get("details", {}).get("events", [])
    if events:
        start = len(rows) + 2
        headers = ["№", "ТС", "Уверенность", "Время (с)", "Сигнал"]
        for j, h in enumerate(headers, 1):
            c = ws.cell(start, j, h)
            c.fill = header_fill
            c.font = header_font
            c.alignment = Alignment(horizontal="center")
        for i, e in enumerate(events, 1):
            ws.cell(start + i, 1, e.get("event_number", i))
            ws.cell(start + i, 2, e.get("vehicle_class", ""))
            ws.cell(start + i, 3, round(e.get("confidence", 0), 2))
            ws.cell(start + i, 4, e.get("time_seconds", ""))
            ws.cell(start + i, 5, signal_labels.get(e.get("traffic_light_state", ""), e.get("traffic_light_state", "")))

    wb.save(str(output))
