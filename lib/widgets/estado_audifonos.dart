import 'package:flutter/material.dart';

import '../servicios/plataforma.dart';

/// Tarjeta que muestra si hay audífonos conectados (se actualiza sola).
class EstadoAudifonos extends StatelessWidget {
  const EstadoAudifonos({super.key, this.audifonoCalibrado});

  /// Nombre del audífono con el que se calibró, para avisar si es otro.
  final String? audifonoCalibrado;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Audifono>>(
      valueListenable: Plataforma.audifonosConectados,
      builder: (context, audifonos, _) {
        if (audifonos.isEmpty) {
          return Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: const ListTile(
              leading: Icon(Icons.headset_off),
              title: Text('Conecta los audífonos'),
              subtitle: Text('La audiometría no se puede hacer con el altavoz del teléfono.'),
            ),
          );
        }
        final a = audifonos.first;
        final avisos = <String>[
          if (a.tipo == 'bluetooth')
            'Bluetooth: usa siempre los mismos audífonos con los que calibraste.',
          if (audifonoCalibrado != null && audifonoCalibrado != a.nombre)
            'Atención: la calibración se hizo con "$audifonoCalibrado".',
        ];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.headphones, color: Colors.green),
            title: Text('Audífonos conectados: ${a.nombre}'),
            subtitle: Text(['Conexión: ${a.tipo}', ...avisos].join('\n')),
            isThreeLine: avisos.isNotEmpty,
          ),
        );
      },
    );
  }
}

bool hayAudifonos() => Plataforma.audifonosConectados.value.isNotEmpty;

void mostrarMensaje(BuildContext context, String texto) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
}

Future<bool> confirmar(BuildContext context, String titulo, String texto) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(titulo),
      content: Text(texto),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Aceptar')),
      ],
    ),
  );
  return r ?? false;
}
