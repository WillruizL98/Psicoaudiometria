"""Análisis de resultados: promedios, clasificación, tablas y exportación CSV."""

import csv
from datetime import datetime

FRECUENCIAS = [250, 500, 1000, 2000, 3000, 4000, 6000, 8000]
NOMBRES_OIDO = {"D": "Oído derecho", "I": "Oído izquierdo"}

# Grados de la OMS (Informe mundial sobre la audición, 2021) sobre el
# promedio de 500, 1000, 2000 y 4000 Hz.
GRADOS_OMS = [
    (20, "Audición normal"),
    (35, "Pérdida leve"),
    (50, "Pérdida moderada"),
    (65, "Pérdida moderadamente severa"),
    (80, "Pérdida severa"),
    (95, "Pérdida profunda"),
    (None, "Pérdida completa"),
]

FRECUENCIAS_PTA_OMS = [500, 1000, 2000, 4000]
FRECUENCIAS_PTA_TRITONAL = [500, 1000, 2000]


def _umbral(prueba, oido, frecuencia):
    return prueba.get("umbrales", {}).get(oido, {}).get(str(frecuencia))


def texto_umbral(umbral):
    if umbral is None:
        return "—"
    if umbral.get("nr"):
        return f"NR (>{umbral['nivel']})"
    return str(umbral["nivel"])


def promedio(prueba, oido, frecuencias):
    """Devuelve (promedio, incluye_sin_respuesta) o (None, False) si faltan datos."""
    valores = [_umbral(prueba, oido, f) for f in frecuencias]
    if any(v is None for v in valores):
        return None, False
    media = sum(v["nivel"] for v in valores) / len(valores)
    return round(media, 1), any(v.get("nr") for v in valores)


def clasificar(pta):
    if pta is None:
        return "Sin datos suficientes"
    for limite, nombre in GRADOS_OMS:
        if limite is None or pta < limite:
            return nombre
    return GRADOS_OMS[-1][1]


def _frecuencias_evaluadas(prueba):
    presentes = set()
    for por_frecuencia in prueba.get("umbrales", {}).values():
        presentes.update(int(f) for f in por_frecuencia)
    return [f for f in FRECUENCIAS if f in presentes]


def _observaciones(prueba, resumen):
    notas = []
    pta_d = resumen["D"]["pta_oms"]
    pta_i = resumen["I"]["pta_oms"]
    if pta_d is not None and pta_i is not None and abs(pta_d - pta_i) >= 15:
        peor = "derecho" if pta_d > pta_i else "izquierdo"
        notas.append(
            f"Asimetría interaural de {abs(pta_d - pta_i):.0f} dB (peor oído {peor}). "
            "Se sugiere valoración por especialista."
        )

    for oido, nombre in NOMBRES_OIDO.items():
        u2 = _umbral(prueba, oido, 2000)
        u4 = _umbral(prueba, oido, 4000)
        u8 = _umbral(prueba, oido, 8000)
        if u2 and u4 and u8 and not u4.get("nr"):
            if u4["nivel"] - u2["nivel"] >= 15 and u4["nivel"] - u8["nivel"] >= 10:
                notas.append(
                    f"{nombre}: muesca en 4 kHz, patrón que suele asociarse a exposición a ruido."
                )
        sin_respuesta = [
            f for f in FRECUENCIAS if (_umbral(prueba, oido, f) or {}).get("nr")
        ]
        if sin_respuesta:
            notas.append(
                f"{nombre}: sin respuesta al nivel máximo en "
                f"{', '.join(str(f) for f in sin_respuesta)} Hz."
            )

    conf = prueba.get("confiabilidad", {})
    falsos = conf.get("falsos_positivos", 0)
    if falsos >= 3:
        notas.append(
            f"Se registraron {falsos} respuestas sin estímulo; la confiabilidad de la prueba es baja."
        )
    if not prueba.get("calibracion", {}).get("calibrado", False):
        notas.append(
            "Prueba realizada sin calibración: los valores en dB HL son solo aproximados."
        )
    if not notas:
        notas.append("Sin hallazgos adicionales.")
    return notas


def _confiabilidad(prueba):
    conf = prueba.get("confiabilidad", {})
    presentaciones = conf.get("presentaciones", 0)
    falsos = conf.get("falsos_positivos", 0)
    if falsos <= 1:
        nivel = "Buena"
    elif falsos <= 3:
        nivel = "Regular"
    else:
        nivel = "Baja"
    return {"presentaciones": presentaciones, "falsos_positivos": falsos, "nivel": nivel}


def analizar(prueba):
    frecuencias = _frecuencias_evaluadas(prueba)

    tabla = []
    for f in frecuencias:
        ud = _umbral(prueba, "D", f)
        ui = _umbral(prueba, "I", f)
        diferencia = "—"
        if ud and ui and not ud.get("nr") and not ui.get("nr"):
            diferencia = str(abs(ud["nivel"] - ui["nivel"]))
        tabla.append(
            {
                "frecuencia": f,
                "D": texto_umbral(ud),
                "I": texto_umbral(ui),
                "diferencia": diferencia,
            }
        )

    resumen = {}
    for oido in NOMBRES_OIDO:
        pta, pta_nr = promedio(prueba, oido, FRECUENCIAS_PTA_OMS)
        tri, tri_nr = promedio(prueba, oido, FRECUENCIAS_PTA_TRITONAL)
        resumen[oido] = {
            "pta_oms": pta,
            "pta_oms_texto": "—" if pta is None else f"{'≥' if pta_nr else ''}{pta:.1f}",
            "pta_tritonal": tri,
            "pta_tritonal_texto": "—" if tri is None else f"{'≥' if tri_nr else ''}{tri:.1f}",
            "grado": clasificar(pta),
        }

    return {
        "frecuencias": frecuencias,
        "tabla": tabla,
        "resumen": resumen,
        "observaciones": _observaciones(prueba, resumen),
        "confiabilidad": _confiabilidad(prueba),
    }


def _fecha_corta(iso):
    try:
        return datetime.fromisoformat(iso).strftime("%Y-%m-%d %H:%M")
    except (TypeError, ValueError):
        return iso or ""


def tabla_historial(pruebas):
    filas = []
    for prueba in pruebas:
        a = analizar(prueba)
        filas.append(
            {
                "id": prueba.get("id"),
                "fecha": _fecha_corta(prueba.get("fecha")),
                "paciente": prueba.get("paciente", {}).get("nombre", ""),
                "pta_D": a["resumen"]["D"]["pta_oms_texto"],
                "pta_I": a["resumen"]["I"]["pta_oms_texto"],
                "grado_D": a["resumen"]["D"]["grado"],
                "grado_I": a["resumen"]["I"]["grado"],
            }
        )
    return filas


def exportar_csv(datos):
    """Escribe todas las pruebas en un CSV (abre bien en Excel) y devuelve la ruta."""
    ruta = datos["ruta"]
    encabezado = ["fecha", "paciente", "documento", "edad", "sexo", "audifono", "calibracion"]
    for oido in ("D", "I"):
        encabezado += [f"{oido}_{f}Hz" for f in FRECUENCIAS]
    encabezado += ["PTA_D", "PTA_I", "grado_D", "grado_I", "falsos_positivos"]

    with open(ruta, "w", newline="", encoding="utf-8-sig") as archivo:
        escritor = csv.writer(archivo, delimiter=";")
        escritor.writerow(encabezado)
        for prueba in datos["pruebas"]:
            a = analizar(prueba)
            paciente = prueba.get("paciente", {})
            fila = [
                _fecha_corta(prueba.get("fecha")),
                paciente.get("nombre", ""),
                paciente.get("documento", ""),
                paciente.get("edad", ""),
                paciente.get("sexo", ""),
                prueba.get("audifono", {}).get("nombre", ""),
                prueba.get("calibracion", {}).get("nombre", ""),
            ]
            for oido in ("D", "I"):
                fila += [
                    texto_umbral(_umbral(prueba, oido, f)) if _umbral(prueba, oido, f) else ""
                    for f in FRECUENCIAS
                ]
            fila += [
                a["resumen"]["D"]["pta_oms_texto"],
                a["resumen"]["I"]["pta_oms_texto"],
                a["resumen"]["D"]["grado"],
                a["resumen"]["I"]["grado"],
                a["confiabilidad"]["falsos_positivos"],
            ]
            escritor.writerow(fila)
    return ruta
