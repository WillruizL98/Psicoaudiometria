import 'dart:convert';
import 'dart:io';

import 'plataforma.dart';

/// Guarda todo como archivos JSON en la memoria interna de la app.
class Almacen {
  static Future<Directory> _carpeta(String nombre) async {
    final base = await Plataforma.directorio();
    final carpeta = Directory('$base/$nombre');
    await carpeta.create(recursive: true);
    return carpeta;
  }

  static Future<List<Map<String, dynamic>>> _leerTodos(String carpeta) async {
    final dir = await _carpeta(carpeta);
    final lista = <Map<String, dynamic>>[];
    await for (final archivo in dir.list()) {
      if (archivo is File && archivo.path.endsWith('.json')) {
        try {
          lista.add(jsonDecode(await archivo.readAsString()) as Map<String, dynamic>);
        } on FormatException {
          // archivo dañado: se ignora
        }
      }
    }
    lista.sort((a, b) => (b['fecha'] as String).compareTo(a['fecha'] as String));
    return lista;
  }

  static Future<void> _guardar(String carpeta, Map<String, dynamic> datos) async {
    final dir = await _carpeta(carpeta);
    await File('${dir.path}/${datos['id']}.json').writeAsString(jsonEncode(datos));
  }

  static Future<void> _borrar(String carpeta, String id) async {
    final archivo = File('${(await _carpeta(carpeta)).path}/$id.json');
    if (await archivo.exists()) await archivo.delete();
  }

  static String nuevoId() {
    final a = DateTime.now();
    String d(int n) => n.toString().padLeft(2, '0');
    return '${a.year}${d(a.month)}${d(a.day)}-${d(a.hour)}${d(a.minute)}${d(a.second)}';
  }

  // Pruebas
  static Future<List<Map<String, dynamic>>> pruebas() => _leerTodos('pruebas');
  static Future<void> guardarPrueba(Map<String, dynamic> p) => _guardar('pruebas', p);
  static Future<void> borrarPrueba(String id) => _borrar('pruebas', id);

  // Calibraciones
  static Future<List<Map<String, dynamic>>> calibraciones() => _leerTodos('calibraciones');
  static Future<void> guardarCalibracion(Map<String, dynamic> c) =>
      _guardar('calibraciones', c);
  static Future<void> borrarCalibracion(String id) async {
    await _borrar('calibraciones', id);
    if (await calibracionActivaId() == id) await fijarCalibracionActiva(null);
  }

  static Future<File> _ajustes() async =>
      File('${await Plataforma.directorio()}/ajustes.json');

  static Future<String?> calibracionActivaId() async {
    final archivo = await _ajustes();
    if (!await archivo.exists()) return null;
    final ajustes = jsonDecode(await archivo.readAsString()) as Map<String, dynamic>;
    return ajustes['calibracion_activa'] as String?;
  }

  static Future<void> fijarCalibracionActiva(String? id) async {
    final archivo = await _ajustes();
    await archivo.writeAsString(jsonEncode({'calibracion_activa': id}));
  }

  /// Perfil activo; si no hay, uno aproximado "sin calibrar" creado por Python.
  static Future<Map<String, dynamic>> calibracionActiva() async {
    final id = await calibracionActivaId();
    if (id != null) {
      for (final c in await calibraciones()) {
        if (c['id'] == id) return c;
      }
    }
    final perfil = Map<String, dynamic>.from(
        await Plataforma.python('calibracion', 'crear_perfil', {'modo': 'defecto'}) as Map);
    return {
      ...perfil,
      'id': 'defecto',
      'nombre': 'Sin calibrar (aproximado)',
      'fecha': DateTime.now().toIso8601String(),
      'audifono': null,
      'volumen': null,
    };
  }

  static Future<String> rutaArchivo(String nombre) async {
    final dir = await _carpeta('informes');
    return '${dir.path}/$nombre';
  }
}
