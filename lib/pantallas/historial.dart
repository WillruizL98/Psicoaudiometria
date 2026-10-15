import 'package:flutter/material.dart';

import '../servicios/almacen.dart';
import '../servicios/plataforma.dart';
import '../widgets/estado_audifonos.dart';
import 'resultado.dart';

/// Tabla con todas las pruebas guardadas y exportación a CSV.
class PantallaHistorial extends StatefulWidget {
  const PantallaHistorial({super.key});

  @override
  State<PantallaHistorial> createState() => _EstadoHistorial();
}

class _EstadoHistorial extends State<PantallaHistorial> {
  List<Map<String, dynamic>> _pruebas = [];
  List<Map> _filas = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final pruebas = await Almacen.pruebas();
      final filas = (await Plataforma.python('analisis', 'tabla_historial', pruebas) as List).cast<Map>();
      setState(() {
        _pruebas = pruebas;
        _filas = filas;
      });
    } catch (e) {
      if (mounted) mostrarMensaje(context, 'Error al cargar: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _exportarCsv() async {
    try {
      final ruta = await Almacen.rutaArchivo('historial_${Almacen.nuevoId()}.csv');
      await Plataforma.python('analisis', 'exportar_csv', {'pruebas': _pruebas, 'ruta': ruta});
      await Plataforma.compartir(ruta, 'text/csv');
    } catch (e) {
      if (mounted) mostrarMensaje(context, 'No se pudo exportar: $e');
    }
  }

  Future<void> _borrar(String id, String nombre) async {
    if (!await confirmar(context, 'Borrar prueba', '¿Borrar la prueba de $nombre?')) return;
    await Almacen.borrarPrueba(id);
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial y tablas'),
        actions: [
          IconButton(
            tooltip: 'Exportar CSV (Excel)',
            onPressed: _pruebas.isEmpty ? null : _exportarCsv,
            icon: const Icon(Icons.table_view),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _filas.isEmpty
              ? const Center(child: Text('Todavía no hay pruebas guardadas.'))
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(8),
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Toca una fila para ver el detalle. Promedios OMS en dB HL.'),
                      ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          showCheckboxColumn: false,
                          columns: const [
                            DataColumn(label: Text('Fecha')),
                            DataColumn(label: Text('Paciente')),
                            DataColumn(label: Text('PTA D'), numeric: true),
                            DataColumn(label: Text('PTA I'), numeric: true),
                            DataColumn(label: Text('Grado D')),
                            DataColumn(label: Text('Grado I')),
                            DataColumn(label: Text('')),
                          ],
                          rows: [
                            for (final f in _filas)
                              DataRow(
                                onSelectChanged: (_) async {
                                  final prueba = _pruebas.firstWhere((p) => p['id'] == f['id']);
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => PantallaResultado(prueba: prueba)),
                                  );
                                },
                                cells: [
                                  DataCell(Text('${f['fecha']}')),
                                  DataCell(Text('${f['paciente']}')),
                                  DataCell(Text('${f['pta_D']}')),
                                  DataCell(Text('${f['pta_I']}')),
                                  DataCell(Text('${f['grado_D']}')),
                                  DataCell(Text('${f['grado_I']}')),
                                  DataCell(IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _borrar(f['id'] as String, f['paciente'] as String),
                                  )),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
