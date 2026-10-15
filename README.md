# Audiometría tonal para Android (Flutter + Python)

Proyecto académico: audiometría de vía aérea que se ejecuta **completamente en el
teléfono**, sin servidores. Flutter dibuja la interfaz; Python (empaquetado con
[Chaquopy](https://chaquo.com/chaquopy/)) hace los cálculos, las tablas y el PDF.

> No reemplaza una audiometría clínica ni constituye un diagnóstico médico.

## Descargar e instalar (sin compilar nada)

1. En el celular, abre la página de
   [**Releases**](https://github.com/WillruizL98/Psicoaudiometria/releases/latest)
   y descarga **`audiometria.apk`**.
2. Ábrelo. Android pedirá permiso para *instalar apps de origen desconocido*
   (para el navegador o el gestor de archivos): actívalo y pulsa **Instalar**.
3. Si aparece Play Protect diciendo que la app no es conocida, elige
   *Más detalles → Instalar de todas formas* (pasa con toda app que no viene de Play Store).

Requisitos: Android 7.0 o superior, celular de 64 bits (casi todos los actuales)
y audífonos (de cable, USB-C o Bluetooth).

**Primer uso:** entra a *Calibración* y calibra tus audífonos (con sonómetro, o la
biológica con una persona de audición normal). Luego *Nueva audiometría*.

## Funciones

- **Exige audífonos**: no deja iniciar sin audífonos (cable, USB-C o Bluetooth) y
  pausa la prueba si se desconectan.
- **Calibración** con dos modos:
  - *Sonómetro*: se mide en dB SPL un tono de referencia de -20 dBFS y se convierte
    a dB HL con los RETSPL de la ISO 389-1.
  - *Biológica*: una persona con audición normal hace la prueba; su umbral se toma
    como 0 dB HL.
  - El perfil guarda el audífono y el volumen del sistema, que la app fija sola en
    cada prueba.
- **Prueba**: método ascendente de Hughson-Westlake modificado (baja 10 dB, sube
  5 dB; umbral = 2 respuestas ascendentes), de 250 a 8000 Hz, en ambos oídos.
  Registra las respuestas sin estímulo (falsos positivos).
- **Tablas**: umbrales por frecuencia, promedios (OMS 0.5–4 kHz y tritonal), grado
  OMS 2021 e historial de todas las pruebas. Exporta a CSV para Excel.
- **Informe PDF** con datos del paciente, audiograma, tablas y observaciones.

## Arquitectura

```
Flutter (Dart)                    Kotlin (Android)                Python (Chaquopy)
lib/pantallas/*  ── canales ──►  MainActivity.kt   ── llama ──►  puente.py
  interfaz, flujo de la prueba    GeneradorTonos.kt              calibracion.py  dB HL ↔ dBFS
lib/logica/procedimiento.dart     detección de audífonos          analisis.py     PTA, grados, tablas, CSV
  algoritmo Hughson-Westlake      volumen, compartir archivos     informe.py      PDF (reportlab)
```

| Carpeta / archivo | Qué hace |
|---|---|
| `lib/logica/procedimiento.dart` | Algoritmo de búsqueda de umbral (con pruebas en `test/`) |
| `lib/pantallas/prueba.dart` | Ejecuta la audiometría: tonos, botón, pausas |
| `lib/servicios/plataforma.dart` | Puente Dart → Kotlin/Python |
| `lib/servicios/almacen.dart` | Guarda pruebas y calibraciones como JSON en el teléfono |
| `android/app/src/main/python/` | Todo el código Python |
| `android/app/src/main/kotlin/.../GeneradorTonos.kt` | Tonos puros estéreo con rampas de 25 ms |

## Cómo compilar e instalar

Requisitos en el PC: Flutter, Android SDK, JDK 17+ y **Python 3.13** (Chaquopy lo
usa al compilar; debe coincidir con `version = "3.13"` en `android/app/build.gradle.kts`).

```bash
flutter test                 # pruebas del algoritmo
flutter build apk --release  # genera build/app/outputs/flutter-apk/app-release.apk
flutter run                  # o instala directo en un teléfono conectado por USB
```

Para instalar en el teléfono: activa *Opciones de desarrollador → Depuración USB*,
conecta el cable y ejecuta `flutter run`, o copia el APK al teléfono y ábrelo.

## Limitaciones (para la discusión del trabajo)

- Los RETSPL de la norma corresponden a audífonos audiométricos (TDH-39), no a
  audífonos comerciales; la calibración con sonómetro casero es aproximada.
- Con un DAC de 16 bits, los niveles cercanos a -10 dB HL pueden quedar bajo el
  ruido del conversor.
- En Bluetooth cada audífono procesa el sonido distinto: hay que calibrar cada uno.
- No hay enmascaramiento ni vía ósea.
- No se mide el ruido ambiental.
