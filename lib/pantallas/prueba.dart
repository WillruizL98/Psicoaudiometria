import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../logica/procedimiento.dart';
import '../servicios/plataforma.dart';
import '../widgets/audiograma.dart';
import '../widgets/estado_audifonos.dart';

/// Orden clínico habitual: 1 kHz, agudos, y luego graves.
const ordenFrecuencias = [1000, 2000, 3000, 4000, 6000, 8000, 500, 250];

class ConfigPrueba {
  const ConfigPrueba({
    required this.frecuencias,
    required this.volumen,
    this.perfil,
    this.esCalibracion = false,
    this.oidos = const ['D', 'I'],
  });

  /// Perfil de calibración (null en la calibración biológica, que trabaja en dBFS).
  final Map<String, dynamic>? perfil;
  final List<int> frecuencias;
  final int volumen;
  final bool esCalibracion;
  final List<String> oidos;
}

/// Ejecuta la audiometría. Devuelve con `Navigator.pop` un mapa con
/// `umbrales`, `confiabilidad`, `audifono` y `duracion_s` (o null si se cancela).
class PantallaPrueba extends StatefulWidget {
  const PantallaPrueba({super.key, required this.config});
  final ConfigPrueba config;

  @override
  State<PantallaPrueba> createState() => _EstadoPrueba();
}

class _EstadoPrueba extends State<PantallaPrueba> with WidgetsBindingObserver {
  static const duracionTonoMs = 1000;
  static const ventanaRespuestaMs = 1300; // tiempo extra para responder tras el tono

  final _azar = Random();
  ConfigPrueba get config => widget.config;

  bool _iniciada = false;
  bool _cancelada = false;
  String? _motivoPausa;
  Completer<void>? _reanudar;

  bool _ventanaAbierta = false;
  bool _respondio = false;
  bool _tonoSonando = false;
  int _falsosPositivos = 0;
  int _presentaciones = 0;

  final Map<String, Map<String, dynamic>> _umbrales = {'D': {}, 'I': {}};
  String _oido = 'D';
  int _frecuencia = 1000;
  int _nivel = 0;
  int _paso = 0;
  Audifono? _audifonoUsado;
  late final DateTime _inicio;

  int get _total => config.oidos.length * config.frecuencias.length;
  String get _unidad => config.esCalibracion ? 'dBFS' : 'dB HL';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Plataforma.audifonosConectados.addListener(_cambioAudifonos);
  }

  @override
  void dispose() {
    _cancelada = true;
    _reanudar?.complete();
    Plataforma.detener();
    WidgetsBinding.instance.removeObserver(this);
    Plataforma.audifonosConectados.removeListener(_cambioAudifonos);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado != AppLifecycleState.resumed && _iniciada) {
      _pausar('La aplicación salió de primer plano.');
    }
  }

  void _cambioAudifonos() {
    if (!hayAudifonos() && _iniciada) {
      _pausar('Se desconectaron los audífonos. Vuelve a conectarlos para continuar.');
    } else if (mounted) {
      setState(() {});
    }
  }

  void _pausar(String motivo) {
    Plataforma.detener();
    _ventanaAbierta = false;
    _tonoSonando = false;
    if (mounted) setState(() => _motivoPausa = motivo);
  }

  void _continuar() {
    if (!hayAudifonos()) {
      mostrarMensaje(context, 'Primero conecta los audífonos.');
      return;
    }
    setState(() => _motivoPausa = null);
    _reanudar?.complete();
    _reanudar = null;
  }

  Future<void> _esperarReanudacion() async {
    while (_motivoPausa != null && !_cancelada) {
      _reanudar ??= Completer<void>();
      await _reanudar!.future;
    }
  }

  /// Espera [ms]; devuelve false si en ese tiempo hubo pausa o cancelación.
  Future<bool> _esperar(int ms) async {
    final fin = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(fin)) {
      if (_cancelada || _motivoPausa != null) return false;
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    return !_cancelada && _motivoPausa == null;
  }

  ({int inicio, int minimo, int maximo})? _limites(String oido, int f) {
    if (config.esCalibracion) return (inicio: -50, minimo: -120, maximo: -10);
    final perfil = config.perfil!;
    final desplazamiento = (perfil['desplazamientos'][oido] as Map?)?['$f'];
    final maximo = (perfil['maximos_hl'][oido] as Map?)?['$f'];
    if (desplazamiento == null || maximo == null) return null;
    final m = (maximo as num).toInt();
    return (inicio: min(40, m), minimo: -10, maximo: m);
  }

  double _dbfs(String oido, int f, int nivel) {
    if (config.esCalibracion) return nivel.toDouble();
    final desplazamiento = (config.perfil!['desplazamientos'][oido] as Map)['$f'] as num;
    return desplazamiento + nivel.toDouble();
  }

  Future<void> _comenzar() async {
    if (!hayAudifonos()) {
      mostrarMensaje(context, 'Conecta los audífonos para comenzar.');
      return;
    }
    _audifonoUsado = Plataforma.audifonosConectados.value.first;
    _inicio = DateTime.now();
    setState(() => _iniciada = true);
    await _ejecutar();
  }

  Future<void> _ejecutar() async {
    for (final oido in config.oidos) {
      for (final f in config.frecuencias) {
        final limites = _limites(oido, f);
        if (limites == null) {
          _paso++;
          continue; // frecuencia sin calibrar
        }
        final proc = ProcedimientoUmbral(
          inicio: limites.inicio,
          minimo: limites.minimo,
          maximo: limites.maximo,
        );
        setState(() {
          _oido = oido;
          _frecuencia = f;
          _nivel = proc.nivel;
        });

        while (!proc.terminado) {
          await _esperarReanudacion();
          if (_cancelada || !mounted) return;
          if (!await _esperar(1200 + _azar.nextInt(1800))) continue;

          final volumen = await Plataforma.fijarVolumen(config.volumen);
          if (volumen.actual != config.volumen) {
            _pausar('El volumen del teléfono cambió y no se pudo restaurar. '
                'Ponlo en ${config.volumen} de ${volumen.maximo} y continúa.');
            continue;
          }

          setState(() {
            _nivel = proc.nivel;
            _respondio = false;
            _ventanaAbierta = true;
            _tonoSonando = true;
          });
          await Plataforma.tono(
            frecuencia: f,
            dbfs: _dbfs(oido, f, proc.nivel),
            oido: oido,
            duracionMs: duracionTonoMs,
          );
          final completo = await _esperar(duracionTonoMs);
          if (mounted) setState(() => _tonoSonando = false);
          final valido = completo && await _esperar(ventanaRespuestaMs);
          _ventanaAbierta = false;
          if (!valido) continue; // estímulo anulado por una pausa: se repite

          _presentaciones++;
          proc.registrar(_respondio);
        }

        setState(() {
          _umbrales[oido]!['$f'] = {'nivel': proc.nivelResultado, 'nr': proc.sinRespuesta};
          _paso++;
        });
      }
    }

    if (!mounted || _cancelada) return;
    Navigator.pop(context, {
      'umbrales': _umbrales,
      'confiabilidad': {
        'presentaciones': _presentaciones,
        'falsos_positivos': _falsosPositivos,
      },
      'audifono': _audifonoUsado?.aMapa(),
      'duracion_s': DateTime.now().difference(_inicio).inSeconds,
    });
  }

  void _pulsar() {
    if (!_iniciada || _motivoPausa != null) return;
    if (_ventanaAbierta) {
      setState(() => _respondio = true);
    } else {
      _falsosPositivos++;
    }
  }

  Future<void> _salir() async {
    if (!_iniciada) {
      Navigator.pop(context);
      return;
    }
    final si = await confirmar(context, '¿Cancelar la prueba?', 'Se perderán los resultados de esta prueba.');
    if (si && mounted) {
      _cancelada = true;
      _reanudar?.complete();
      Plataforma.detener();
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final colorOido = _oido == 'D' ? colorDerecho : colorIzquierdo;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _salir();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(config.esCalibracion ? 'Calibración biológica' : 'Audiometría'),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: _salir),
        ),
        body: SafeArea(
          child: !_iniciada
              ? _instrucciones(tema)
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      LinearProgressIndicator(value: _total == 0 ? 0 : _paso / _total),
                      const SizedBox(height: 12),
                      Text(
                        '${_oido == 'D' ? 'Oído derecho' : 'Oído izquierdo'} · $_frecuencia Hz',
                        style: tema.textTheme.titleLarge?.copyWith(color: colorOido),
                      ),
                      Text('Nivel actual: $_nivel $_unidad  ·  Estímulos: $_presentaciones',
                          style: tema.textTheme.bodySmall),
                      if (!config.esCalibracion) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 190,
                          child: Audiograma(
                            umbrales: _umbrales,
                            resaltar: (_oido, _frecuencia, _nivel),
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (_motivoPausa != null)
                        _tarjetaPausa(tema)
                      else
                        _botonRespuesta(colorOido),
                      const Spacer(),
                      Text(
                        'Pulsa el botón cada vez que oigas un pitido, aunque sea muy débil.',
                        textAlign: TextAlign.center,
                        style: tema.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _botonRespuesta(Color color) {
    final activo = _respondio && _ventanaAbierta;
    return GestureDetector(
      onTapDown: (_) => _pulsar(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 210,
        height: 210,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: activo ? color : color.withValues(alpha: 0.15),
          border: Border.all(color: color, width: 4),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hearing, size: 64, color: activo ? Colors.white : color),
            Text(
              '¡LO ESCUCHÉ!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: activo ? Colors.white : color,
              ),
            ),
            if (_tonoSonando && config.esCalibracion)
              const Text('♪', style: TextStyle(fontSize: 18)),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaPausa(ThemeData tema) {
    return Card(
      color: tema.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pause_circle, size: 48),
            const SizedBox(height: 8),
            Text(_motivoPausa!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _continuar,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _instrucciones(ThemeData tema) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const EstadoAudifonos(),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Antes de empezar', style: tema.textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text('1. Busca un lugar muy silencioso.'),
                const Text('2. Ponte los audífonos: el derecho (R) en el oído derecho y el izquierdo (L) en el izquierdo.'),
                const Text('3. No toques el volumen; la app lo fija automáticamente.'),
                const Text('4. Oirás pitidos de distintos tonos, a veces muy débiles. '
                    'Pulsa el botón cada vez que oigas uno.'),
                const Text('5. No pulses si no estás seguro de haber oído algo.'),
                const SizedBox(height: 8),
                Text(
                  'Se evaluarán ${config.frecuencias.length} frecuencias en '
                  '${config.oidos.length == 2 ? 'ambos oídos' : 'un oído'} '
                  '(aprox. ${(_total * 1.2).ceil()} min).',
                  style: tema.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ValueListenableBuilder(
          valueListenable: Plataforma.audifonosConectados,
          builder: (context, audifonos, _) => FilledButton.icon(
            onPressed: audifonos.isEmpty ? null : _comenzar,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Comenzar'),
          ),
        ),
      ],
    );
  }
}
