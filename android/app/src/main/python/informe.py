"""Generación del informe PDF con reportlab (todo se ejecuta en el teléfono)."""

import math
from datetime import datetime
from xml.sax.saxutils import escape

from reportlab.graphics.shapes import Circle, Drawing, Line, PolyLine, Rect, String
from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import KeepTogether, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

import analisis

COLOR_D = colors.HexColor("#C62828")
COLOR_I = colors.HexColor("#1565C0")
COLOR_GUIA = colors.HexColor("#B0BEC5")
COLOR_CABECERA = colors.HexColor("#ECEFF1")

FRECUENCIAS_GRAFICA = [250, 500, 1000, 2000, 3000, 4000, 6000, 8000]
NIVEL_MIN, NIVEL_MAX = -10, 120

SEXOS = {"F": "Femenino", "M": "Masculino", "O": "Otro"}


def _t(texto):
    return escape(str(texto if texto not in (None, "") else "—"))


def _fecha(iso):
    try:
        return datetime.fromisoformat(iso).strftime("%d/%m/%Y %H:%M")
    except (TypeError, ValueError):
        return iso or "—"


def dibujar_audiograma(prueba, ancho=17 * cm, alto=8 * cm):
    d = Drawing(ancho, alto)
    izq, der, arriba, abajo = 1.5 * cm, 0.4 * cm, 0.6 * cm, 0.9 * cm
    x0, x1 = izq, ancho - der
    y_sup, y_inf = alto - arriba, abajo

    def x(f):
        return x0 + (x1 - x0) * math.log2(f / 250) / math.log2(8000 / 250)

    def y(nivel):
        return y_sup - (y_sup - y_inf) * (nivel - NIVEL_MIN) / (NIVEL_MAX - NIVEL_MIN)

    # Zona de audición normal (-10 a 20 dB HL)
    d.add(Rect(x0, y(20), x1 - x0, y(NIVEL_MIN) - y(20),
               fillColor=colors.HexColor("#E8F5E9"), strokeColor=None))

    for nivel in range(NIVEL_MIN, NIVEL_MAX + 1, 10):
        d.add(Line(x0, y(nivel), x1, y(nivel), strokeColor=COLOR_GUIA, strokeWidth=0.4))
        d.add(String(x0 - 4, y(nivel) - 3, str(nivel), fontSize=7, fontName="Helvetica", textAnchor="end"))
    for f in FRECUENCIAS_GRAFICA:
        d.add(Line(x(f), y_inf, x(f), y_sup, strokeColor=COLOR_GUIA, strokeWidth=0.4))
        etiqueta = f"{f // 1000}k" if f >= 1000 else str(f)
        d.add(String(x(f), y_sup + 4, etiqueta, fontSize=7, fontName="Helvetica", textAnchor="middle"))
    d.add(String(x0 - 30, y_sup + 4, "Hz", fontSize=7, fontName="Helvetica"))
    d.add(String(2, (y_sup + y_inf) / 2, "dB HL", fontSize=7, fontName="Helvetica"))
    d.add(Rect(x0, y_inf, x1 - x0, y_sup - y_inf, fillColor=None,
               strokeColor=colors.black, strokeWidth=0.8))

    r = 4
    for oido, color in (("D", COLOR_D), ("I", COLOR_I)):
        puntos = []
        for f in FRECUENCIAS_GRAFICA:
            u = prueba.get("umbrales", {}).get(oido, {}).get(str(f))
            if not u:
                continue
            px, py = x(f), y(u["nivel"])
            if oido == "D":
                d.add(Circle(px, py, r, fillColor=None, strokeColor=color, strokeWidth=1.3))
            else:
                d.add(Line(px - r, py - r, px + r, py + r, strokeColor=color, strokeWidth=1.3))
                d.add(Line(px - r, py + r, px + r, py - r, strokeColor=color, strokeWidth=1.3))
            if u.get("nr"):
                # flecha hacia abajo: sin respuesta al nivel máximo
                d.add(Line(px, py - r, px, py - 3 * r, strokeColor=color, strokeWidth=1))
                d.add(Line(px, py - 3 * r, px - 2, py - 3 * r + 3, strokeColor=color, strokeWidth=1))
                d.add(Line(px, py - 3 * r, px + 2, py - 3 * r + 3, strokeColor=color, strokeWidth=1))
            else:
                puntos += [px, py]
        if len(puntos) >= 4:
            d.add(PolyLine(puntos, strokeColor=color, strokeWidth=1,
                           strokeDashArray=[3, 2] if oido == "I" else None))

    # Leyenda debajo de la gráfica
    ly = 6
    lx = x0
    d.add(Circle(lx + 4, ly + 3, 3.5, fillColor=None, strokeColor=COLOR_D, strokeWidth=1.2))
    d.add(String(lx + 12, ly, "Oído derecho (O)", fontSize=7.5, fontName="Helvetica", fillColor=COLOR_D))
    lx += 110
    d.add(Line(lx + 1, ly, lx + 7, ly + 6, strokeColor=COLOR_I, strokeWidth=1.2))
    d.add(Line(lx + 1, ly + 6, lx + 7, ly, strokeColor=COLOR_I, strokeWidth=1.2))
    d.add(String(lx + 12, ly, "Oído izquierdo (X)", fontSize=7.5, fontName="Helvetica", fillColor=COLOR_I))
    lx += 115
    d.add(Line(lx, ly + 5, lx, ly - 1, strokeColor=colors.black, strokeWidth=1))
    d.add(String(lx + 6, ly, "Sin respuesta (NR)", fontSize=7.5, fontName="Helvetica"))
    lx += 105
    d.add(Rect(lx, ly - 1, 10, 7, fillColor=colors.HexColor("#E8F5E9"), strokeColor=None))
    d.add(String(lx + 14, ly, "Rango normal", fontSize=7.5, fontName="Helvetica"))
    return d


def _estilo_tabla(con_cabecera=True):
    estilo = [
        ("FONT", (0, 0), (-1, -1), "Helvetica", 9),
        ("GRID", (0, 0), (-1, -1), 0.4, COLOR_GUIA),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 2),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
    ]
    if con_cabecera:
        estilo += [
            ("FONT", (0, 0), (-1, 0), "Helvetica-Bold", 9),
            ("BACKGROUND", (0, 0), (-1, 0), COLOR_CABECERA),
        ]
    return TableStyle(estilo)


def _pie(canvas, doc):
    canvas.saveState()
    canvas.setFont("Helvetica", 7.5)
    canvas.setFillColor(colors.grey)
    canvas.drawString(
        doc.leftMargin, 1.2 * cm,
        "Trabajo académico. Este informe no constituye un diagnóstico médico.",
    )
    canvas.drawRightString(
        doc.pagesize[0] - doc.rightMargin, 1.2 * cm,
        f"Generado {datetime.now().strftime('%d/%m/%Y %H:%M')} · Página {doc.page}",
    )
    canvas.restoreState()


def generar_pdf(datos):
    prueba = datos["prueba"]
    ruta = datos["ruta"]
    a = analisis.analizar(prueba)

    estilos = getSampleStyleSheet()
    titulo = ParagraphStyle("titulo", parent=estilos["Title"], fontSize=17, spaceAfter=2)
    subtitulo = ParagraphStyle("sub", parent=estilos["Normal"], fontSize=9,
                               textColor=colors.grey, alignment=1)
    seccion = ParagraphStyle("sec", parent=estilos["Heading3"], spaceBefore=6, spaceAfter=3)
    normal = ParagraphStyle("normal", parent=estilos["Normal"], fontSize=9, leading=12)

    paciente = prueba.get("paciente", {})
    cal = prueba.get("calibracion", {})
    aud = prueba.get("audifono", {})
    vol = prueba.get("volumen", {})
    conf = a["confiabilidad"]

    elementos = [
        Paragraph("Informe de audiometría tonal", titulo),
        Paragraph("Vía aérea · Método ascendente (Hughson-Westlake modificado)", subtitulo),
        Spacer(1, 2),
        Paragraph("Datos del paciente", seccion),
    ]

    ancho_util = letter[0] - 3.6 * cm
    datos_paciente = [
        ["Nombre", Paragraph(_t(paciente.get("nombre")), normal),
         "Documento", Paragraph(_t(paciente.get("documento")), normal)],
        ["Edad", _t(paciente.get("edad")), "Sexo",
         _t(SEXOS.get(paciente.get("sexo"), paciente.get("sexo")))],
        ["Fecha", _fecha(prueba.get("fecha")), "Examinador",
         Paragraph(_t(prueba.get("examinador")), normal)],
    ]
    t = Table(datos_paciente, colWidths=[3.0 * cm, ancho_util / 2 - 3.0 * cm] * 2)
    t.setStyle(_estilo_tabla(False))
    t.setStyle(TableStyle([
        ("FONT", (0, 0), (0, -1), "Helvetica-Bold", 9),
        ("FONT", (2, 0), (2, -1), "Helvetica-Bold", 9),
        ("BACKGROUND", (0, 0), (0, -1), COLOR_CABECERA),
        ("BACKGROUND", (2, 0), (2, -1), COLOR_CABECERA),
    ]))
    elementos.append(t)

    elementos.append(Paragraph("Equipo y condiciones", seccion))
    modo = {"sonometro": "Sonómetro (RETSPL ISO 389-1)", "biologica": "Biológica",
            "defecto": "Sin calibrar (aproximado)"}.get(cal.get("modo"), cal.get("modo"))
    equipo = [
        ["Audífonos", Paragraph(_t(f"{aud.get('nombre', '')} ({aud.get('tipo', '')})"), normal),
         "Calibración", Paragraph(_t(f"{cal.get('nombre', '')} · {modo}"), normal)],
        ["Volumen sistema", f"{vol.get('nivel', '—')} / {vol.get('maximo', '—')}",
         "Confiabilidad",
         f"{conf['nivel']} ({conf['falsos_positivos']} falsas resp. / {conf['presentaciones']} estímulos)"],
    ]
    t = Table(equipo, colWidths=[3.0 * cm, ancho_util / 2 - 3.0 * cm] * 2)
    t.setStyle(_estilo_tabla(False))
    t.setStyle(TableStyle([
        ("FONT", (0, 0), (0, -1), "Helvetica-Bold", 9),
        ("FONT", (2, 0), (2, -1), "Helvetica-Bold", 9),
        ("BACKGROUND", (0, 0), (0, -1), COLOR_CABECERA),
        ("BACKGROUND", (2, 0), (2, -1), COLOR_CABECERA),
    ]))
    elementos.append(t)

    elementos.append(Paragraph("Audiograma", seccion))
    elementos.append(dibujar_audiograma(prueba))

    elementos.append(Paragraph("Umbrales auditivos (dB HL)", seccion))
    # Tabla horizontal: una columna por frecuencia
    filas = [
        ["Hz"] + [str(f["frecuencia"]) for f in a["tabla"]],
        ["Derecho"] + [f["D"] for f in a["tabla"]],
        ["Izquierdo"] + [f["I"] for f in a["tabla"]],
        ["Diferencia"] + [f["diferencia"] for f in a["tabla"]],
    ]
    columnas = max(1, len(a["tabla"]))
    t = Table(filas, colWidths=[2.4 * cm] + [(ancho_util - 2.4 * cm) / columnas] * columnas)
    t.setStyle(_estilo_tabla())
    t.setStyle(TableStyle([
        ("ALIGN", (1, 0), (-1, -1), "CENTER"),
        ("FONT", (0, 1), (0, -1), "Helvetica-Bold", 9),
        ("FONTSIZE", (1, 1), (-1, -1), 8.5),
        ("TEXTCOLOR", (0, 1), (-1, 1), COLOR_D),
        ("TEXTCOLOR", (0, 2), (-1, 2), COLOR_I),
    ]))
    elementos.append(t)

    elementos.append(Paragraph("Resumen", seccion))
    r = a["resumen"]
    filas = [
        ["", "Oído derecho", "Oído izquierdo"],
        ["Promedio OMS (0.5–4 kHz)", r["D"]["pta_oms_texto"], r["I"]["pta_oms_texto"]],
        ["Promedio tritonal (0.5–2 kHz)", r["D"]["pta_tritonal_texto"], r["I"]["pta_tritonal_texto"]],
        ["Grado (OMS 2021)", Paragraph(_t(r["D"]["grado"]), normal),
         Paragraph(_t(r["I"]["grado"]), normal)],
    ]
    t = Table(filas, colWidths=[ancho_util * 0.4, ancho_util * 0.3, ancho_util * 0.3])
    t.setStyle(_estilo_tabla())
    t.setStyle(TableStyle([("FONT", (0, 1), (0, -1), "Helvetica-Bold", 9)]))
    elementos.append(KeepTogether([elementos.pop(), t]))

    elementos.append(Paragraph("Observaciones", seccion))
    for nota in a["observaciones"]:
        elementos.append(Paragraph(f"• {_t(nota)}", normal))
    if paciente.get("observaciones"):
        elementos.append(Spacer(1, 4))
        elementos.append(Paragraph(f"<b>Del examinador:</b> {_t(paciente['observaciones'])}", normal))

    doc = SimpleDocTemplate(
        ruta, pagesize=letter,
        leftMargin=1.8 * cm, rightMargin=1.8 * cm, topMargin=1.1 * cm, bottomMargin=1.8 * cm,
        title="Informe de audiometría", author=str(prueba.get("examinador") or ""),
    )
    doc.build(elementos, onFirstPage=_pie, onLaterPages=_pie)
    return ruta
