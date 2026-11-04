import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/auth_layout.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../files/domain/file_item.dart' show formatearFecha;
import '../domain/auth_repository.dart';
import '../domain/cuenta.dart';
import 'auth_providers.dart';

/// Dónde está abierta tu cuenta, como en la cuenta de Google. Las sesiones
/// no vencen solas: desde acá se cierran.
class DispositivosScreen extends ConsumerWidget {
  const DispositivosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lista = ref.watch(dispositivosProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.perfil)),
        title: const Text('Dispositivos conectados'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(dispositivosProvider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
                  child: Text(
                    'Seguís conectado en estos dispositivos hasta que cierres la sesión. '
                    'Si no reconocés alguno, cerralo y cambiá tu contraseña. '
                    'Al cerrarlo, deja de tener acceso en unos minutos.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
                ...lista.when(
                  loading: () => [const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))],
                  error: (_, _) => [
                    ListTile(
                      leading: const Icon(Icons.cloud_off_outlined),
                      title: const Text('No pudimos cargar tus dispositivos'),
                      trailing: TextButton(
                        onPressed: () => ref.invalidate(dispositivosProvider),
                        child: const Text('Reintentar'),
                      ),
                    ),
                  ],
                  data: (ds) => [
                    Card(
                      child: Column(children: [
                        for (final (i, d) in ds.indexed) ...[
                          if (i > 0) const Divider(height: 1, indent: 72),
                          _Fila(dispositivo: d),
                        ],
                      ]),
                    ),
                    if (ds.where((d) => !d.actual).isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.logout),
                          label: const Text('Cerrar sesión en los demás'),
                          onPressed: () => _cerrarOtros(context, ref),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _cerrarOtros(BuildContext context, WidgetRef ref) async {
    final ok = await confirmar(
      context,
      titulo: '¿Cerrar sesión en los demás dispositivos?',
      mensaje: 'Vas a seguir conectado solo en este. En los otros te va a pedir que entres de nuevo.',
      accion: 'Cerrar sesiones',
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(authRepositoryProvider).cerrarOtrasSesiones();
      if (!context.mounted) return;
      ref.invalidate(dispositivosProvider);
      mostrarMensaje(context, 'Listo, solo queda este dispositivo');
    } on AuthFailure catch (e) {
      if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }
}

class _Fila extends ConsumerWidget {
  const _Fila({required this.dispositivo});
  final Dispositivo dispositivo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = dispositivo;
    final scheme = Theme.of(context).colorScheme;
    final movil = d.esApp || d.nombre.contains('Android') || d.nombre.contains('iOS');
    final detalle = [
      d.actual ? 'Este dispositivo' : 'Activo ${formatearFecha(d.ultimoUso, DateTime.now())}',
      if (d.ip != null) d.ip!,
    ].join(' · ');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: d.actual ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        child: Icon(
          movil ? Icons.smartphone_outlined : Icons.laptop_outlined,
          color: d.actual ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
      title: Text(d.nombre),
      subtitle: Text(detalle,
          style: d.actual ? TextStyle(color: scheme.primary, fontWeight: FontWeight.w500) : null),
      trailing: d.actual
          ? null
          : IconButton(
              tooltip: 'Cerrar sesión ahí',
              icon: const Icon(Icons.logout),
              onPressed: () => _cerrar(context, ref),
            ),
    );
  }

  Future<void> _cerrar(BuildContext context, WidgetRef ref) async {
    final ok = await confirmar(
      context,
      titulo: '¿Cerrar sesión en ${dispositivo.nombre}?',
      mensaje: 'Si vuelve a usarse, va a tener que entrar de nuevo.',
      accion: 'Cerrar sesión',
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(authRepositoryProvider).cerrarDispositivo(dispositivo.id);
      if (!context.mounted) return;
      ref.invalidate(dispositivosProvider);
      mostrarMensaje(context, 'Se cerró la sesión en ${dispositivo.nombre}');
    } on AuthFailure catch (e) {
      if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }
}
