import 'package:flutter/material.dart';

import 'pantallas/calibracion.dart';
import 'pantallas/historial.dart';
import 'pantallas/nueva_prueba.dart';
import 'servicios/almacen.dart';
import 'servicios/plataforma.dart';
import 'widgets/estado_audifonos.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Plataforma.iniciarMonitoreoAudifonos();
  runApp(const AppAudiometria());
}

class AppAudiometria extends StatelessWidget {
  const AppAudiometria({super.key});

  @override
  Widget build(BuildContext context) {
    const semilla = Color(0xFF00796B);
    return MaterialApp(
      title: 'Audiometría',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: semilla, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: semilla, brightness: Brightness.dark, useMaterial3: true),
      home: const PantallaInicio(),
    );
  }
}

class PantallaInicio extends StatefulWidget {
  const PantallaInicio({super.key});

  @override
  State<PantallaInicio> createState() => _EstadoInicio();
}

class _EstadoInicio extends State<PantallaInicio> {
  Map<String, dynamic>? _calibracion;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final c = await Almacen.calibracionActiva();
      setState(() {
        _calibracion = c;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _ir(Widget pantalla) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final calibrado = _calibracion?['calibrado'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Audiometría tonal')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const EstadoAudifonos(),
          Card(
            child: ListTile(
              leading: Icon(
                calibrado ? Icons.verified : Icons.warning_amber,
                color: calibrado ? Colors.green : Colors.orange,
              ),
              title: Text(_calibracion == null
                  ? (_error == null ? 'Cargando calibración…' : 'Error al iniciar Python')
                  : 'Calibración: ${_calibracion!['nombre']}'),
              subtitle: Text(_error ??
                  (calibrado
                      ? 'Perfil activo'
                      : 'Calibra tus audífonos para obtener valores reales en dB HL')),
              onTap: () => _ir(const PantallaCalibraciones()),
            ),
          ),
          const SizedBox(height: 16),
          _Opcion(
            icono: Icons.hearing,
            titulo: 'Nueva audiometría',
            texto: 'Datos del paciente y prueba de umbrales por vía aérea',
            alTocar: () => _ir(const PantallaNuevaPrueba()),
            destacada: true,
          ),
          _Opcion(
            icono: Icons.table_chart,
            titulo: 'Historial y tablas',
            texto: 'Resultados guardados, informes PDF y exportación CSV',
            alTocar: () => _ir(const PantallaHistorial()),
          ),
          _Opcion(
            icono: Icons.tune,
            titulo: 'Calibración',
            texto: 'Con sonómetro o biológica',
            alTocar: () => _ir(const PantallaCalibraciones()),
          ),
          const SizedBox(height: 24),
          Text(
            'Proyecto académico. Todo se procesa en este teléfono (Flutter + Python); '
            'no se envían datos a ningún servidor. No reemplaza una audiometría clínica.',
            style: tema.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Opcion extends StatelessWidget {
  const _Opcion({
    required this.icono,
    required this.titulo,
    required this.texto,
    required this.alTocar,
    this.destacada = false,
  });

  final IconData icono;
  final String titulo;
  final String texto;
  final VoidCallback alTocar;
  final bool destacada;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Card(
      color: destacada ? colores.primaryContainer : null,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: Icon(icono, size: 36, color: colores.primary),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(texto),
        trailing: const Icon(Icons.chevron_right),
        onTap: alTocar,
      ),
    );
  }
}
