import 'package:audiometria/logica/procedimiento.dart';
import 'package:flutter_test/flutter_test.dart';

/// Simula un oyente que oye todo lo que esté en [umbralReal] o por encima.
int? simular(int umbralReal, {int maximo = 90}) {
  final p = ProcedimientoUmbral(inicio: 40, minimo: -10, maximo: maximo);
  while (!p.terminado) {
    p.registrar(p.nivel >= umbralReal);
  }
  return p.sinRespuesta ? null : p.umbral;
}

void main() {
  test('encuentra el umbral de un oyente ideal', () {
    for (final u in [-10, 0, 5, 20, 35, 40, 55, 70, 85, 90]) {
      expect(simular(u), u, reason: 'umbral real $u');
    }
  });

  test('sin respuesta cuando el umbral supera el máximo', () {
    expect(simular(95), isNull);
  });

  test('el umbral exige dos respuestas ascendentes', () {
    final p = ProcedimientoUmbral(inicio: 40, minimo: -10, maximo: 90);
    p.registrar(true); // 40 familiarización -> 30
    p.registrar(false); // 30 -> 35
    p.registrar(true); // 35 ascendente (1) -> 25
    expect(p.terminado, isFalse);
    p.registrar(false); // 25 -> 30
    p.registrar(false); // 30 -> 35
    p.registrar(true); // 35 ascendente (2)
    expect(p.umbral, 35);
  });

  test('termina aunque las respuestas sean aleatorias', () {
    final p = ProcedimientoUmbral(inicio: 40, minimo: -10, maximo: 90);
    var i = 0;
    while (!p.terminado) {
      p.registrar(i++ % 3 == 0);
    }
    expect(p.presentaciones, lessThanOrEqualTo(40));
  });
}
