import 'dart:math';

/// Búsqueda de umbral con el método ascendente de Hughson-Westlake modificado:
/// - Familiarización: se empieza en [inicio]; si no oye, se sube 20 dB.
/// - Si oye: se baja 10 dB. Si no oye: se sube 5 dB.
/// - Umbral: el nivel más bajo oído 2 veces en presentaciones ascendentes.
///
/// Los niveles son enteros en la unidad que se quiera (dB HL en la prueba,
/// dBFS en la calibración biológica).
class ProcedimientoUmbral {
  ProcedimientoUmbral({
    required int inicio,
    required this.minimo,
    required this.maximo,
    this.maxPresentaciones = 40,
  }) : nivel = inicio.clamp(minimo, maximo);

  final int minimo;
  final int maximo;
  final int maxPresentaciones;

  /// Nivel del próximo estímulo.
  int nivel;
  int presentaciones = 0;
  int? umbral;
  bool sinRespuesta = false;

  bool _familiarizacion = true;
  bool _ascendente = false;
  final Map<int, int> _respuestasAscendentes = {};

  bool get terminado => umbral != null || sinRespuesta;

  /// Registra si el paciente oyó el estímulo presentado en [nivel].
  void registrar(bool oyo) {
    if (terminado) return;
    presentaciones++;

    if (_familiarizacion) {
      if (oyo) {
        _familiarizacion = false;
        nivel = max(nivel - 10, minimo);
      } else if (nivel >= maximo) {
        sinRespuesta = true;
        return;
      } else {
        nivel = min(nivel + 20, maximo);
      }
    } else if (oyo) {
      if (_ascendente || nivel == minimo) {
        final veces = (_respuestasAscendentes[nivel] ?? 0) + 1;
        _respuestasAscendentes[nivel] = veces;
        if (veces >= 2) {
          umbral = nivel;
          return;
        }
      }
      _ascendente = false;
      nivel = max(nivel - 10, minimo);
    } else {
      _ascendente = true;
      nivel = min(nivel + 5, maximo);
    }

    if (presentaciones >= maxPresentaciones) {
      // Demasiados estímulos: se toma el nivel más bajo con al menos una respuesta.
      final oidos = _respuestasAscendentes.keys.toList()..sort();
      if (oidos.isNotEmpty) {
        umbral = oidos.first;
      } else {
        sinRespuesta = true;
      }
    }
  }

  /// Nivel que se guarda en el resultado (el máximo si no hubo respuesta).
  int get nivelResultado => umbral ?? maximo;
}
