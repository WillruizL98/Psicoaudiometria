import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Audífono conectado según Android.
class Audifono {
  const Audifono({required this.nombre, required this.tipo});

  factory Audifono.desdeMapa(Map<dynamic, dynamic> m) =>
      Audifono(nombre: m['nombre'] as String, tipo: m['tipo'] as String);

  final String nombre;
  final String tipo; // cable, usb, bluetooth

  Map<String, dynamic> aMapa() => {'nombre': nombre, 'tipo': tipo};
}

class EstadoVolumen {
  const EstadoVolumen(this.actual, this.maximo);
  final int actual;
  final int maximo;
}

class ErrorPython implements Exception {
  ErrorPython(this.mensaje);
  final String mensaje;
  @override
  String toString() => 'Error en Python: $mensaje';
}

/// Acceso a lo que vive en Kotlin: audio, audífonos, Python y archivos.
class Plataforma {
  static const _audio = MethodChannel('audiometria/audio');
  static const _python = MethodChannel('audiometria/python');
  static const _sistema = MethodChannel('audiometria/sistema');
  static const _eventosAudifonos = EventChannel('audiometria/audifonos');

  static List<Audifono> _lista(dynamic datos) => (datos as List)
      .map((m) => Audifono.desdeMapa(m as Map))
      .toList();

  static Future<List<Audifono>> audifonos() async =>
      _lista(await _audio.invokeMethod('audifonos'));

  /// Audífonos conectados ahora mismo; se actualiza solo al conectar/desconectar.
  static final audifonosConectados = ValueNotifier<List<Audifono>>(const []);
  static StreamSubscription<List<Audifono>>? _suscripcionAudifonos;

  /// Se llama una vez al abrir la app.
  static void iniciarMonitoreoAudifonos() {
    _suscripcionAudifonos ??= _eventosAudifonos
        .receiveBroadcastStream()
        .map(_lista)
        .listen((lista) => audifonosConectados.value = lista);
  }

  static EstadoVolumen _volumen(dynamic m) =>
      EstadoVolumen((m as Map)['actual'] as int, m['maximo'] as int);

  static Future<EstadoVolumen> volumen() async =>
      _volumen(await _audio.invokeMethod('volumen'));

  static Future<EstadoVolumen> fijarVolumen(int nivel, {bool mostrar = false}) async =>
      _volumen(await _audio.invokeMethod('fijarVolumen', {'nivel': nivel, 'mostrar': mostrar}));

  static Future<void> tono({
    required num frecuencia,
    required num dbfs,
    required String oido,
    required int duracionMs,
  }) =>
      _audio.invokeMethod('tono', {
        'frecuencia': frecuencia.toDouble(),
        'dbfs': dbfs.toDouble(),
        'oido': oido,
        'duracionMs': duracionMs,
      });

  static Future<void> detener() => _audio.invokeMethod('detener');

  /// Llama a `modulo.funcion(datos)` en Python. Los datos viajan como JSON.
  static Future<dynamic> python(String modulo, String funcion, [Object? datos]) async {
    final respuesta = await _python.invokeMethod<String>('llamar', {
      'modulo': modulo,
      'funcion': funcion,
      'datos': jsonEncode(datos),
    });
    final mapa = jsonDecode(respuesta!) as Map<String, dynamic>;
    if (mapa['ok'] != true) throw ErrorPython(mapa['error'] as String);
    return mapa['resultado'];
  }

  static Future<String> directorio() async =>
      (await _sistema.invokeMethod<String>('directorio'))!;

  static Future<void> compartir(String ruta, String tipo) =>
      _sistema.invokeMethod('compartir', {'ruta': ruta, 'tipo': tipo});

  static Future<void> abrir(String ruta, String tipo) =>
      _sistema.invokeMethod('abrir', {'ruta': ruta, 'tipo': tipo});
}
