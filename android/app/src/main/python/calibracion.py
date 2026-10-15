"""Calibración: convierte dB HL (nivel audiométrico) en dBFS (nivel digital).

Todo perfil se reduce a un desplazamiento por oído y frecuencia:

    dBFS = dB HL + desplazamiento[oído][frecuencia]

Modos:
- ``sonometro``: se reproduce un tono de referencia (``ref_dbfs``) y se mide
  con un sonómetro los dB SPL que salen del audífono. Con los RETSPL se pasa
  de dB SPL a dB HL.
- ``biologica``: una persona con audición normal hace la prueba en dBFS; su
  umbral se toma como 0 dB HL (o ``referencia_hl``).
- ``defecto``: estimación sin medir (0 dBFS ≈ 100 dB SPL). Solo para practicar.
"""

import math

FRECUENCIAS = [250, 500, 1000, 2000, 3000, 4000, 6000, 8000]
OIDOS = ["D", "I"]

# RETSPL (dB SPL equivalentes a 0 dB HL) para audífono supraaural TDH-39,
# ISO 389-1. En audífonos comerciales es una aproximación.
RETSPL = {
    125: 45.0,
    250: 25.5,
    500: 11.5,
    750: 8.0,
    1000: 7.0,
    1500: 6.5,
    2000: 9.0,
    3000: 10.0,
    4000: 9.5,
    6000: 15.5,
    8000: 13.0,
}

REF_DBFS = -20.0
DBFS_MAXIMO = -3.0  # margen para no saturar
HL_MINIMO = -10
HL_MAXIMO = 100
DBFS_PISO_RUIDO = -96.0  # límite práctico de un DAC de 16 bits


def info(_datos=None):
    return {
        "frecuencias": FRECUENCIAS,
        "retspl": {str(f): v for f, v in RETSPL.items()},
        "ref_dbfs": REF_DBFS,
        "dbfs_maximo": DBFS_MAXIMO,
    }


def _por_oido(valores, oido):
    """Acepta {"D": {...}, "I": {...}} o un único dict para ambos oídos."""
    if oido in valores:
        return valores[oido]
    return valores


def _desplazamientos_sonometro(datos):
    ref = float(datos.get("ref_dbfs", REF_DBFS))
    mediciones = datos["mediciones"]
    desplazamientos = {}
    for oido in OIDOS:
        medidas_oido = _por_oido(mediciones, oido)
        desplazamientos[oido] = {}
        for f in FRECUENCIAS:
            spl = medidas_oido.get(str(f))
            if spl is None:
                continue
            # SPL producido a X dBFS = spl + (X - ref). Para dB HL = 0 se necesita SPL = RETSPL.
            desplazamientos[oido][str(f)] = round(ref - float(spl) + RETSPL[f], 1)
    return desplazamientos


def _desplazamientos_biologica(datos):
    referencia = float(datos.get("referencia_hl", 0))
    umbrales = datos["umbrales_dbfs"]
    desplazamientos = {}
    for oido in OIDOS:
        desplazamientos[oido] = {}
        for f in FRECUENCIAS:
            u = umbrales.get(oido, {}).get(str(f))
            if u is None:
                continue
            nivel = u["nivel"] if isinstance(u, dict) else u
            if isinstance(u, dict) and u.get("nr"):
                continue  # sin respuesta: no sirve como referencia
            desplazamientos[oido][str(f)] = round(float(nivel) - referencia, 1)
    return desplazamientos


def _desplazamientos_defecto(_datos):
    return {
        oido: {str(f): round(-100.0 + RETSPL[f], 1) for f in FRECUENCIAS}
        for oido in OIDOS
    }


def niveles_maximos(desplazamientos):
    """Máximo dB HL (múltiplo de 5) alcanzable sin pasar de DBFS_MAXIMO."""
    maximos = {}
    for oido, por_frecuencia in desplazamientos.items():
        maximos[oido] = {}
        for f, desplazamiento in por_frecuencia.items():
            maximo = math.floor((DBFS_MAXIMO - desplazamiento) / 5) * 5
            maximos[oido][f] = int(max(HL_MINIMO, min(HL_MAXIMO, maximo)))
    return maximos


def crear_perfil(datos):
    modo = datos.get("modo", "defecto")
    calculos = {
        "sonometro": _desplazamientos_sonometro,
        "biologica": _desplazamientos_biologica,
        "defecto": _desplazamientos_defecto,
    }
    if modo not in calculos:
        raise ValueError(f"Modo de calibración desconocido: {modo}")
    desplazamientos = calculos[modo](datos)

    advertencias = []
    for oido in OIDOS:
        faltan = [f for f in FRECUENCIAS if str(f) not in desplazamientos.get(oido, {})]
        if faltan:
            nombre = "derecho" if oido == "D" else "izquierdo"
            advertencias.append(
                f"Oído {nombre}: sin calibrar en {', '.join(str(f) for f in faltan)} Hz "
                "(esas frecuencias no se podrán evaluar)."
            )

    maximos = niveles_maximos(desplazamientos)
    for oido in OIDOS:
        for f, maximo in maximos.get(oido, {}).items():
            if maximo < 50:
                advertencias.append(
                    f"{f} Hz ({oido}): el audífono solo alcanza {maximo} dB HL."
                )
        bajo_ruido = [
            f
            for f, desplazamiento in desplazamientos.get(oido, {}).items()
            if desplazamiento + HL_MINIMO < DBFS_PISO_RUIDO
        ]
        if bajo_ruido:
            advertencias.append(
                f"Oído {oido}, {', '.join(bajo_ruido)} Hz: los niveles cercanos a -10 dB HL "
                "quedan bajo el ruido del conversor de 16 bits. Si ves umbrales muy bajos "
                "imposibles de oír, calibra con un volumen del sistema menor."
            )

    return {
        "modo": modo,
        "calibrado": modo != "defecto",
        "desplazamientos": desplazamientos,
        "maximos_hl": maximos,
        "minimo_hl": HL_MINIMO,
        "ref_dbfs": datos.get("ref_dbfs", REF_DBFS) if modo == "sonometro" else None,
        "mediciones": datos.get("mediciones") if modo == "sonometro" else None,
        "umbrales_referencia": datos.get("umbrales_dbfs") if modo == "biologica" else None,
        "advertencias": advertencias,
    }
