import 'package:flutter/material.dart';

import '../servicios/almacen.dart';
import '../servicios/plataforma.dart';
import '../widgets/audiograma.dart';
import '../widgets/estado_audifonos.dart';

/// Audiograma, tablas y resumen de una prueba (calculados en Python) + PDF.
class PantallaResultado extends StatefulWidget {
  const PantallaResultado({super.key, required this.prueba});
  final Map<String, dynamic> prueba;

  @override
  State<PantallaResultado> createState() => _EstadoResultado();
}

class _EstadoResultado extends State<PantallaResultado> {
  late final Future<Map<String, dynamic>> _analisis = Plataforma.python(
    'analisis',
    'analizar',
    widget.prueba,
  ).then((r) => Map<String, dynamic>.from(r as Map));
  bool _generando = false;
  String? _rutaPdf;

  Future<void> _generarPdf() async {
    setState(() => _generando = true);
    try {
      final paciente = (widget.prueba['paciente']['nombre'] as String)
          .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      final ruta = await Almacen.rutaArchivo('informe_${widget.prueba['id']}_$paciente.pdf');
      await Plataforma.python('informe', 'generar_pdf', {'prueba': widget.prueba, 'ruta': ruta});
      setState(() => _rutaPdf = ruta);
      if (mounted) mostrarMensaje(context, 'Informe PDF generado.');
    } catch (e) {
      if (mounted) mostrarMensaje(context, 'No se pudo generar el PDF: $e');
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  Future<void> _accion(Future<void> Function(String, String) accion) async {
    try {
      await accion(_rutaPdf!, 'application/pdf');
    } catch (e) {
      if (mounted) mostrarMensaje(context, 'No se pudo: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.prueba;
    final paciente = p['paciente'] as Map;
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Resultados')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _analisis,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error en el análisis: ${snap.error}'));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final a = snap.data!;
          final resumen = a['resumen'] as Map;
          final conf = a['confiabilidad'] as Map;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(paciente['nombre'] as String, style: tema.textTheme.titleLarge),
              Text(
                [
                  if ((paciente['documento'] as String?)?.isNotEmpty ?? false) 'Doc. ${paciente['documento']}',
                  if (paciente['edad'] != null) '${paciente['edad']} años',
                  (p['fecha'] as String).substring(0, 16).replaceFirst('T', ' '),
                ].join(' · '),
              ),
              Text('Calibración: ${p['calibracion']['nombre']}', style: tema.textTheme.bodySmall),
              const SizedBox(height: 12),
              Audiograma(umbrales: Map<String, dynamic>.from(p['umbrales'] as Map)),
              const LeyendaAudiograma(),
              const SizedBox(height: 16),
              Text('Umbrales (dB HL)', style: tema.textTheme.titleMedium),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 24,
                  columns: const [
                    DataColumn(label: Text('Hz'), numeric: true),
                    DataColumn(label: Text('Derecho', style: TextStyle(color: colorDerecho))),
                    DataColumn(label: Text('Izquierdo', style: TextStyle(color: colorIzquierdo))),
                    DataColumn(label: Text('Dif.')),
                  ],
                  rows: [
                    for (final fila in (a['tabla'] as List).cast<Map>())
                      DataRow(cells: [
                        DataCell(Text('${fila['frecuencia']}')),
                        DataCell(Text('${fila['D']}')),
                        DataCell(Text('${fila['I']}')),
                        DataCell(Text('${fila['diferencia']}')),
                      ]),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('Resumen', style: tema.textTheme.titleMedium),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('')),
                    DataColumn(label: Text('Derecho')),
                    DataColumn(label: Text('Izquierdo')),
                  ],
                  rows: [
                    DataRow(cells: [
                      const DataCell(Text('Promedio OMS\n(0.5–4 kHz)')),
                      DataCell(Text('${resumen['D']['pta_oms_texto']}')),
                      DataCell(Text('${resumen['I']['pta_oms_texto']}')),
                    ]),
                    DataRow(cells: [
                      const DataCell(Text('Promedio tritonal\n(0.5–2 kHz)')),
                      DataCell(Text('${resumen['D']['pta_tritonal_texto']}')),
                      DataCell(Text('${resumen['I']['pta_tritonal_texto']}')),
                    ]),
                    DataRow(cells: [
                      const DataCell(Text('Grado (OMS)')),
                      DataCell(Text('${resumen['D']['grado']}')),
                      DataCell(Text('${resumen['I']['grado']}')),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Confiabilidad: ${conf['nivel']} (${conf['falsos_positivos']} respuestas sin estímulo, '
                '${conf['presentaciones']} estímulos)',
              ),
              const SizedBox(height: 16),
              Text('Observaciones', style: tema.textTheme.titleMedium),
              for (final nota in (a['observaciones'] as List)) Text('• $nota'),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _generando ? null : _generarPdf,
                icon: _generando
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.picture_as_pdf),
                label: Text(_rutaPdf == null ? 'Generar informe PDF' : 'Volver a generar PDF'),
              ),
              if (_rutaPdf != null)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _accion(Plataforma.abrir),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Abrir'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _accion(Plataforma.compartir),
                        icon: const Icon(Icons.share),
                        label: const Text('Compartir'),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 24),
              Text(
                'Trabajo académico: estos resultados no constituyen un diagnóstico médico.',
                style: tema.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }
}
