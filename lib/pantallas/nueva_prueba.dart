import 'package:flutter/material.dart';

import '../servicios/almacen.dart';
import '../servicios/plataforma.dart';
import '../widgets/estado_audifonos.dart';
import 'prueba.dart';
import 'resultado.dart';

/// Datos del paciente y preparación de la prueba.
class PantallaNuevaPrueba extends StatefulWidget {
  const PantallaNuevaPrueba({super.key});

  @override
  State<PantallaNuevaPrueba> createState() => _EstadoNuevaPrueba();
}

class _EstadoNuevaPrueba extends State<PantallaNuevaPrueba> {
  final _formulario = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _documento = TextEditingController();
  final _edad = TextEditingController();
  final _examinador = TextEditingController();
  final _observaciones = TextEditingController();
  String _sexo = 'F';
  final Set<int> _frecuencias = {...ordenFrecuencias};
  bool _ambosOidos = true;
  String _primerOido = 'D';

  List<Map<String, dynamic>> _perfiles = [];
  Map<String, dynamic>? _perfil;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarPerfiles();
  }

  Future<void> _cargarPerfiles() async {
    try {
      final activo = await Almacen.calibracionActiva();
      final guardados = await Almacen.calibraciones();
      final defecto = activo['id'] == 'defecto'
          ? activo
          : {
              ...Map<String, dynamic>.from(await Plataforma.python(
                  'calibracion', 'crear_perfil', {'modo': 'defecto'}) as Map),
              'id': 'defecto',
              'nombre': 'Sin calibrar (aproximado)',
            };
      setState(() {
        _perfiles = [...guardados, defecto];
        _perfil = _perfiles.firstWhere((p) => p['id'] == activo['id'], orElse: () => defecto);
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      mostrarMensaje(context, 'No se pudo cargar la calibración: $e');
    }
  }

  @override
  void dispose() {
    for (final c in [_nombre, _documento, _edad, _examinador, _observaciones]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _iniciar() async {
    if (!_formulario.currentState!.validate()) return;
    if (_frecuencias.isEmpty) {
      mostrarMensaje(context, 'Elige al menos una frecuencia.');
      return;
    }
    if (!hayAudifonos()) {
      mostrarMensaje(context, 'Conecta los audífonos para continuar.');
      return;
    }
    final perfil = _perfil!;
    final estado = await Plataforma.volumen();
    final volumen = (perfil['volumen'] as int?) ?? estado.maximo;
    final fijado = await Plataforma.fijarVolumen(volumen, mostrar: true);
    if (!mounted) return;
    if (fijado.actual != volumen) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ajusta el volumen'),
          content: Text(
            'Android no dejó poner el volumen en $volumen de ${fijado.maximo} '
            '(está en ${fijado.actual}). Súbelo con los botones del teléfono, '
            'acepta la advertencia de volumen alto si aparece y vuelve a pulsar "Iniciar".',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
        ),
      );
      return;
    }

    final oidos = _ambosOidos
        ? (_primerOido == 'D' ? ['D', 'I'] : ['I', 'D'])
        : [_primerOido];
    final resultado = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => PantallaPrueba(
          config: ConfigPrueba(
            perfil: perfil,
            frecuencias: ordenFrecuencias.where(_frecuencias.contains).toList(),
            volumen: volumen,
            oidos: oidos,
          ),
        ),
      ),
    );
    if (resultado == null || !mounted) return;

    final prueba = <String, dynamic>{
      'id': Almacen.nuevoId(),
      'fecha': DateTime.now().toIso8601String(),
      'paciente': {
        'nombre': _nombre.text.trim(),
        'documento': _documento.text.trim(),
        'edad': int.tryParse(_edad.text.trim()),
        'sexo': _sexo,
        'observaciones': _observaciones.text.trim(),
      },
      'examinador': _examinador.text.trim(),
      'calibracion': {
        'id': perfil['id'],
        'nombre': perfil['nombre'],
        'modo': perfil['modo'],
        'fecha': perfil['fecha'],
        'calibrado': perfil['calibrado'] == true,
      },
      'volumen': {'nivel': volumen, 'maximo': fijado.maximo},
      ...resultado,
    };
    await Almacen.guardarPrueba(prueba);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => PantallaResultado(prueba: prueba)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva audiometría')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formulario,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  EstadoAudifonos(audifonoCalibrado: (_perfil?['audifono'] as Map?)?['nombre'] as String?),
                  const SizedBox(height: 12),
                  Text('Paciente', style: tema.textTheme.titleMedium),
                  TextFormField(
                    controller: _nombre,
                    decoration: const InputDecoration(labelText: 'Nombre completo *'),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe el nombre' : null,
                  ),
                  TextFormField(
                    controller: _documento,
                    decoration: const InputDecoration(labelText: 'Documento de identidad'),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _edad,
                          decoration: const InputDecoration(labelText: 'Edad'),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            final n = int.tryParse(v.trim());
                            return (n == null || n < 0 || n > 120) ? 'Edad no válida' : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _sexo,
                          decoration: const InputDecoration(labelText: 'Sexo'),
                          items: const [
                            DropdownMenuItem(value: 'F', child: Text('Femenino')),
                            DropdownMenuItem(value: 'M', child: Text('Masculino')),
                            DropdownMenuItem(value: 'O', child: Text('Otro')),
                          ],
                          onChanged: (v) => setState(() => _sexo = v!),
                        ),
                      ),
                    ],
                  ),
                  TextFormField(
                    controller: _examinador,
                    decoration: const InputDecoration(labelText: 'Examinador'),
                  ),
                  TextFormField(
                    controller: _observaciones,
                    decoration: const InputDecoration(labelText: 'Observaciones / antecedentes'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 20),
                  Text('Configuración', style: tema.textTheme.titleMedium),
                  DropdownButtonFormField<String>(
                    initialValue: _perfil?['id'] as String?,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Perfil de calibración'),
                    items: [
                      for (final p in _perfiles)
                        DropdownMenuItem(value: p['id'] as String, child: Text(p['nombre'] as String)),
                    ],
                    onChanged: (id) => setState(
                        () => _perfil = _perfiles.firstWhere((p) => p['id'] == id)),
                  ),
                  if (_perfil?['calibrado'] != true)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Sin calibración los resultados en dB HL son solo aproximados.',
                        style: TextStyle(color: tema.colorScheme.error),
                      ),
                    ),
                  const SizedBox(height: 12),
                  const Text('Frecuencias (Hz)'),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final f in [...ordenFrecuencias]..sort())
                        FilterChip(
                          label: Text('$f'),
                          selected: _frecuencias.contains(f),
                          onSelected: (s) => setState(() => s ? _frecuencias.add(f) : _frecuencias.remove(f)),
                        ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Evaluar ambos oídos'),
                    value: _ambosOidos,
                    onChanged: (v) => setState(() => _ambosOidos = v),
                  ),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'D', label: Text(_ambosOidos ? 'Empezar por derecho' : 'Solo derecho')),
                      ButtonSegment(value: 'I', label: Text(_ambosOidos ? 'Empezar por izquierdo' : 'Solo izquierdo')),
                    ],
                    selected: {_primerOido},
                    onSelectionChanged: (s) => setState(() => _primerOido = s.first),
                  ),
                  const SizedBox(height: 24),
                  ValueListenableBuilder(
                    valueListenable: Plataforma.audifonosConectados,
                    builder: (context, audifonos, _) => FilledButton.icon(
                      onPressed: audifonos.isEmpty || _perfil == null ? null : _iniciar,
                      icon: const Icon(Icons.hearing),
                      label: const Text('Iniciar audiometría'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
