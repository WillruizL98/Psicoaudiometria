import 'dart:math';

import 'package:flutter/material.dart';

const colorDerecho = Color(0xFFC62828);
const colorIzquierdo = Color(0xFF1565C0);
const frecuenciasAudiograma = [250, 500, 1000, 2000, 3000, 4000, 6000, 8000];

/// Audiograma clásico: frecuencia en escala logarítmica, dB HL hacia abajo,
/// O roja = oído derecho, X azul = oído izquierdo.
class Audiograma extends StatelessWidget {
  const Audiograma({super.key, required this.umbrales, this.resaltar});

  /// {"D": {"1000": {"nivel": 20, "nr": false}}, "I": {...}}
  final Map<String, dynamic> umbrales;

  /// Punto que se está evaluando (oído, frecuencia, nivel), opcional.
  final (String, int, int)? resaltar;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.25,
      child: CustomPaint(
        painter: _PintorAudiograma(
          umbrales,
          resaltar,
          Theme.of(context).colorScheme,
        ),
      ),
    );
  }
}

class _PintorAudiograma extends CustomPainter {
  _PintorAudiograma(this.umbrales, this.resaltar, this.colores);

  final Map<String, dynamic> umbrales;
  final (String, int, int)? resaltar;
  final ColorScheme colores;

  static const nivelMin = -10;
  static const nivelMax = 120;

  @override
  void paint(Canvas canvas, Size size) {
    const izq = 34.0, der = 10.0, arriba = 22.0, abajo = 6.0;
    final area = Rect.fromLTRB(izq, arriba, size.width - der, size.height - abajo);

    double x(int f) => area.left + area.width * (log(f / 250) / log(32));
    double y(num nivel) =>
        area.top + area.height * (nivel - nivelMin) / (nivelMax - nivelMin);

    canvas.drawRect(
      Rect.fromLTRB(area.left, y(nivelMin), area.right, y(20)),
      Paint()..color = Colors.green.withValues(alpha: 0.10),
    );

    final guia = Paint()
      ..color = colores.outlineVariant
      ..strokeWidth = 0.7;
    final estiloTexto = TextStyle(fontSize: 10, color: colores.onSurfaceVariant);

    void texto(String t, Offset centro, {bool derecha = false}) {
      final tp = TextPainter(
        text: TextSpan(text: t, style: estiloTexto),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = derecha ? centro.dx - tp.width : centro.dx - tp.width / 2;
      tp.paint(canvas, Offset(dx, centro.dy - tp.height / 2));
    }

    for (var nivel = nivelMin; nivel <= nivelMax; nivel += 10) {
      canvas.drawLine(Offset(area.left, y(nivel)), Offset(area.right, y(nivel)), guia);
      texto('$nivel', Offset(area.left - 4, y(nivel)), derecha: true);
    }
    for (final f in frecuenciasAudiograma) {
      canvas.drawLine(Offset(x(f), area.top), Offset(x(f), area.bottom), guia);
      texto(f >= 1000 ? '${f ~/ 1000}k' : '$f', Offset(x(f), arriba / 2));
    }
    canvas.drawRect(
      area,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = colores.outline,
    );

    for (final (oido, color) in [('D', colorDerecho), ('I', colorIzquierdo)]) {
      final datos = (umbrales[oido] as Map?) ?? {};
      final pincel = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      Offset? anterior;
      for (final f in frecuenciasAudiograma) {
        final u = datos['$f'] as Map?;
        if (u == null) continue;
        final p = Offset(x(f), y(u['nivel'] as num));
        final nr = u['nr'] == true;
        if (!nr && anterior != null) {
          _linea(canvas, anterior, p, pincel, discontinua: oido == 'I');
        }
        if (!nr) anterior = p;
        _simbolo(canvas, oido, p, pincel);
        if (nr) {
          canvas.drawLine(p + const Offset(0, 6), p + const Offset(0, 16), pincel);
          canvas.drawLine(p + const Offset(0, 16), p + const Offset(-4, 11), pincel);
          canvas.drawLine(p + const Offset(0, 16), p + const Offset(4, 11), pincel);
        }
      }
    }

    if (resaltar case (final oido, final f, final nivel)) {
      final color = oido == 'D' ? colorDerecho : colorIzquierdo;
      canvas.drawCircle(
        Offset(x(f), y(nivel.clamp(nivelMin, nivelMax))),
        10,
        Paint()..color = color.withValues(alpha: 0.25),
      );
    }
  }

  void _simbolo(Canvas canvas, String oido, Offset p, Paint pincel) {
    const r = 6.0;
    if (oido == 'D') {
      canvas.drawCircle(p, r, pincel);
    } else {
      canvas.drawLine(p + const Offset(-r, -r), p + const Offset(r, r), pincel);
      canvas.drawLine(p + const Offset(-r, r), p + const Offset(r, -r), pincel);
    }
  }

  void _linea(Canvas canvas, Offset a, Offset b, Paint pincel, {required bool discontinua}) {
    if (!discontinua) {
      canvas.drawLine(a, b, pincel);
      return;
    }
    final total = (b - a).distance;
    final dir = (b - a) / total;
    for (var d = 0.0; d < total; d += 9) {
      canvas.drawLine(a + dir * d, a + dir * min(d + 5, total), pincel);
    }
  }

  @override
  bool shouldRepaint(covariant _PintorAudiograma viejo) => true;
}

class LeyendaAudiograma extends StatelessWidget {
  const LeyendaAudiograma({super.key});

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 16,
      children: [
        Text('O  Oído derecho', style: TextStyle(color: colorDerecho, fontWeight: FontWeight.bold)),
        Text('X  Oído izquierdo', style: TextStyle(color: colorIzquierdo, fontWeight: FontWeight.bold)),
        Text('↓  Sin respuesta'),
      ],
    );
  }
}
