import 'dart:async';

import 'package:flutter/material.dart';

import '../servicios/almacen.dart';
import '../servicios/plataforma.dart';
import '../widgets/estado_audifonos.dart';
import 'prueba.dart';

const _refDbfs = -20.0;

/// Lista de perfiles de calibración guardados.
class PantallaCalibraciones extends StatefulWidget {
  const PantallaCalibraciones({super.key});

  @override
  State<PantallaCalibraciones> createState() => _EstadoCalibraciones();
}

class _EstadoCalibraciones extends State<PantallaCalibraciones> {
  List<Map<String, dynamic>> _perfiles = [];
  String? _activa;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final perfiles = await Almacen.calibraciones();
    final activa = await Almacen.calibracionActivaId();
    setState(() {
      _perfiles = perfiles;
      _activa = activa;
    });
  }

  Future<void> _nueva(Widget pantalla) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Calibración')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'La calibración relaciona el nivel digital del teléfono (dBFS) con el nivel '
            'audiométrico (dB HL) para un audífono y un volumen concretos. '
            'Calibra cada par de audífonos que vayas a usar.',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _nueva(const PantallaCalibracionSonometro()),
                  icon: const Icon(Icons.speed),
                  label: const Text('Con sonómetro'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _nueva(const PantallaCalibracionBiologica()),
                  icon: const Icon(Icons.person),
                  label: const Text('Biológica'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Perfiles guardados', style: tema.textTheme.titleMedium),
          if (_perfiles.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No hay calibraciones. Mientras tanto se usa un perfil aproximado.'),
            ),
          RadioGroup<String>(
            groupValue: _activa,
            onChanged: (id) async {
              await Almacen.fijarCalibracionActiva(id);
              _cargar();
            },
            child: Column(
              children: [
                for (final p in _perfiles)
                  Card(
                    child: RadioListTile<String>(
                      value: p['id'] as String,
                      title: Text(p['nombre'] as String),
                      subtitle: Text(
                        '${p['modo'] == 'sonometro' ? 'Sonómetro' : 'Biológica'} · '
                        '${(p['fecha'] as String).substring(0, 10)} · '
                        '${(p['audifono'] as Map?)?['nombre'] ?? 'audífono ?'} · '
                        'volumen ${p['volumen']}',
                      ),
                      secondary: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (await confirmar(context, 'Borrar calibración', '¿Borrar "${p['nombre']}"?')) {
                            await Almacen.borrarCalibracion(p['id'] as String);
                            _cargar();
                          }
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Selector del volumen del sistema con el que se calibra (y luego se evalúa).
class _SelectorVolumen extends StatelessWidget {
  const _SelectorVolumen({required this.volumen, required this.maximo, required this.alCambiar});
  final int volumen;
  final int maximo;
  final ValueChanged<int> alCambiar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Volumen del sistema: $volumen de $maximo'),
        Slider(
          value: volumen.toDouble(),
          min: 1,
          max: maximo.toDouble(),
          divisions: maximo > 1 ? maximo - 1 : null,
          label: '$volumen',
          onChanged: (v) => alCambiar(v.round()),
        ),
        Text(
          'La prueba usará siempre este mismo volumen. Normalmente el máximo; '
          'bájalo si los audífonos son muy sensibles.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

mixin _ConVolumen<T extends StatefulWidget> on State<T> {
  int volumen = 1;
  int volumenMaximo = 1;

  Future<void> cargarVolumen() async {
    final v = await Plataforma.volumen();
    setState(() {
      volumenMaximo = v.maximo;
      volumen = v.maximo;
    });
  }

  Future<bool> aplicarVolumen() async {
    final v = await Plataforma.fijarVolumen(volumen, mostrar: true);
    if (v.actual != volumen && mounted) {
      mostrarMensaje(context,
          'Android no dejó fijar el volumen en $volumen. Súbelo con los botones y acepta la advertencia.');
      return false;
    }
    return true;
  }

  Future<void> guardarPerfil(Map<String, dynamic> datos, String nombre) async {
    final perfil = Map<String, dynamic>.from(
        await Plataforma.python('calibracion', 'crear_perfil', datos) as Map);
    final completo = {
      ...perfil,
      'id': 'cal-${Almacen.nuevoId()}',
      'nombre': nombre,
      'fecha': DateTime.now().toIso8601String(),
      'audifono': Plataforma.audifonosConectados.value.firstOrNull?.aMapa(),
      'volumen': volumen,
      'volumen_maximo': volumenMaximo,
    };
    await Almacen.guardarCalibracion(completo);
    await Almacen.fijarCalibracionActiva(completo['id'] as String);
    if (!mounted) return;
    final advertencias = (perfil['advertencias'] as List).cast<String>();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Calibración guardada'),
        content: SingleChildScrollView(
          child: Text([
            'Quedó como perfil activo.',
            if (advertencias.isNotEmpty) '\nAvisos:',
            ...advertencias.map((a) => '• $a'),
          ].join('\n')),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Aceptar'))],
      ),
    );
    if (mounted) Navigator.pop(context);
  }
}

/// Calibración con sonómetro: se reproduce un tono de referencia y se
/// anota cuántos dB SPL mide el sonómetro en el auricular.
class PantallaCalibracionSonometro extends StatefulWidget {
  const PantallaCalibracionSonometro({super.key});

  @override
  State<PantallaCalibracionSonometro> createState() => _EstadoSonometro();
}

class _EstadoSonometro extends State<PantallaCalibracionSonometro> with _ConVolumen {
  static const frecuencias = [250, 500, 1000, 2000, 3000, 4000, 6000, 8000];
  final _nombre = TextEditingController(text: 'Calibración sonómetro');
  final _campos = {
    for (final o in ['D', 'I'])
      for (final f in frecuencias) '$o$f': TextEditingController(),
  };
  bool _mismoValor = true;
  String? _sonando; // clave "D1000"
  Timer? _temporizador;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    cargarVolumen();
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    Plataforma.detener();
    _nombre.dispose();
    for (final c in _campos.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _reproducir(String oido, int f) async {
    final clave = '$oido$f';
    _temporizador?.cancel();
    await Plataforma.detener();
    if (!mounted) return;
    if (_sonando == clave) {
      setState(() => _sonando = null);
      return;
    }
    if (!hayAudifonos()) {
      mostrarMensaje(context, 'Conecta los audífonos.');
      return;
    }
    if (!await aplicarVolumen()) return;
    await Plataforma.tono(
      frecuencia: f,
      dbfs: _refDbfs,
      oido: _mismoValor ? 'A' : oido,
      duracionMs: 8000,
    );
    setState(() => _sonando = clave);
    _temporizador = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _sonando = null);
    });
  }

  Future<void> _guardar() async {
    final mediciones = <String, Map<String, double>>{'D': {}, 'I': {}};
    for (final o in ['D', 'I']) {
      for (final f in frecuencias) {
        final texto = _campos['${_mismoValor ? 'D' : o}$f']!.text.trim().replaceAll(',', '.');
        if (texto.isEmpty) continue;
        final valor = double.tryParse(texto);
        if (valor == null || valor < 20 || valor > 140) {
          mostrarMensaje(context, 'Valor no válido en $f Hz: "$texto" (esperado 20–140 dB SPL).');
          return;
        }
        mediciones[o]!['$f'] = valor;
      }
    }
    if (mediciones['D']!.isEmpty && mediciones['I']!.isEmpty) {
      mostrarMensaje(context, 'Anota al menos una medición.');
      return;
    }
    setState(() => _guardando = true);
    try {
      await guardarPerfil({'modo': 'sonometro', 'ref_dbfs': _refDbfs, 'mediciones': mediciones},
          _nombre.text.trim().isEmpty ? 'Calibración sonómetro' : _nombre.text.trim());
    } catch (e) {
      if (mounted) mostrarMensaje(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Widget _filaOido(String oido, int f) {
    final clave = '$oido$f';
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: () => _reproducir(oido, f),
          icon: Icon(_sonando == clave ? Icons.stop : Icons.play_arrow),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _campos[clave],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: _mismoValor ? 'dB SPL medidos' : 'dB SPL ${oido == 'D' ? 'derecho' : 'izquierdo'}',
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Calibración con sonómetro')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const EstadoAudifonos(),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '1. Coloca el micrófono del sonómetro pegado al auricular (idealmente con un acoplador '
                'o un vaso de espuma que selle el auricular).\n'
                '2. Sonómetro en ponderación Z (o C) y respuesta lenta.\n'
                '3. Toca ▶ en cada frecuencia: suena un tono de referencia (${_refDbfs.toStringAsFixed(0)} dBFS, 8 s).\n'
                '4. Anota los dB SPL medidos.\n'
                '⚠ El tono es fuerte: no te pongas los audífonos durante la medición.',
                style: tema.textTheme.bodySmall,
              ),
            ),
          ),
          TextField(controller: _nombre, decoration: const InputDecoration(labelText: 'Nombre del perfil')),
          const SizedBox(height: 12),
          _SelectorVolumen(
            volumen: volumen,
            maximo: volumenMaximo,
            alCambiar: (v) => setState(() => volumen = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mismo valor para ambos auriculares'),
            subtitle: const Text('Desactívalo para medir cada lado por separado.'),
            value: _mismoValor,
            onChanged: (v) => setState(() => _mismoValor = v),
          ),
          for (final f in frecuencias) ...[
            const Divider(),
            Text('$f Hz', style: tema.textTheme.titleSmall),
            _filaOido('D', f),
            if (!_mismoValor) _filaOido('I', f),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: const Icon(Icons.save),
            label: const Text('Calcular y guardar'),
          ),
        ],
      ),
    );
  }
}

/// Calibración biológica: una persona con audición normal hace la prueba
/// en dBFS; su umbral se toma como 0 dB HL.
class PantallaCalibracionBiologica extends StatefulWidget {
  const PantallaCalibracionBiologica({super.key});

  @override
  State<PantallaCalibracionBiologica> createState() => _EstadoBiologica();
}

class _EstadoBiologica extends State<PantallaCalibracionBiologica> with _ConVolumen {
  final _nombre = TextEditingController(text: 'Calibración biológica');
  final _oyente = TextEditingController();
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    cargarVolumen();
  }

  @override
  void dispose() {
    _nombre.dispose();
    _oyente.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    if (!hayAudifonos()) {
      mostrarMensaje(context, 'Conecta los audífonos.');
      return;
    }
    if (!await aplicarVolumen() || !mounted) return;
    final resultado = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => PantallaPrueba(
          config: ConfigPrueba(
            esCalibracion: true,
            frecuencias: ordenFrecuencias,
            volumen: volumen,
          ),
        ),
      ),
    );
    if (resultado == null || !mounted) return;
    setState(() => _guardando = true);
    try {
      final nombre = _nombre.text.trim().isEmpty ? 'Calibración biológica' : _nombre.text.trim();
      final oyente = _oyente.text.trim();
      await guardarPerfil(
        {'modo': 'biologica', 'umbrales_dbfs': resultado['umbrales'], 'referencia_hl': 0},
        oyente.isEmpty ? nombre : '$nombre ($oyente)',
      );
    } catch (e) {
      if (mounted) mostrarMensaje(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calibración biológica')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const EstadoAudifonos(),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Una persona joven (18–30 años) sin problemas de audición hace la prueba completa '
                'en un cuarto muy silencioso. Sus umbrales se toman como 0 dB HL para estos audífonos.\n\n'
                'Es menos exacta que el sonómetro, pero no necesita equipo. Para mayor precisión, '
                'repítela con varias personas y quédate con la más consistente.',
              ),
            ),
          ),
          TextField(controller: _nombre, decoration: const InputDecoration(labelText: 'Nombre del perfil')),
          TextField(controller: _oyente, decoration: const InputDecoration(labelText: 'Persona de referencia')),
          const SizedBox(height: 12),
          _SelectorVolumen(
            volumen: volumen,
            maximo: volumenMaximo,
            alCambiar: (v) => setState(() => volumen = v),
          ),
          const SizedBox(height: 20),
          ValueListenableBuilder(
            valueListenable: Plataforma.audifonosConectados,
            builder: (context, audifonos, _) => FilledButton.icon(
              onPressed: audifonos.isEmpty || _guardando ? null : _iniciar,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Iniciar calibración'),
            ),
          ),
        ],
      ),
    );
  }
}
