import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/push/push.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/auth_layout.dart';
import '../../files/domain/file_item.dart' show formatearFecha;
import '../../groups/presentation/group_shell.dart' show Aviso;
import '../domain/notificacion.dart';
import 'notificaciones_providers.dart';

/// La campanita: abre el centro de notificaciones, con cuántas hay sin leer.
class BotonNotificaciones extends ConsumerWidget {
  const BotonNotificaciones({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(sinLeerProvider).value ?? 0;
    return IconButton(
      tooltip: n == 0 ? 'Notificaciones' : 'Notificaciones ($n sin leer)',
      onPressed: () => context.push(Routes.notificaciones),
      icon: Badge(
        isLabelVisible: n > 0,
        label: Text(n > 99 ? '99+' : '$n'),
        child: Icon(n > 0 ? Icons.notifications : Icons.notifications_none),
      ),
    );
  }
}

class NotificacionesScreen extends ConsumerWidget {
  const NotificacionesScreen({super.key});

  Future<void> _abrir(BuildContext context, WidgetRef ref, Notificacion n) async {
    if (!n.leida) {
      // Con el contenedor, no con la pantalla (que puede cerrarse antes).
      final container = ProviderScope.containerOf(context);
      container.read(notificacionesRepositoryProvider).marcarLeida(n.id).then((_) {
        container.invalidate(sinLeerProvider);
        container.invalidate(notificacionesProvider);
      }, onError: (_) {});
    }
    if (rutaValida(n.ruta)) context.push(n.ruta);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lista = ref.watch(notificacionesProvider);
    final haySinLeer = lista.value?.any((n) => !n.leida) ?? false;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.grupos)),
        title: const Text('Notificaciones'),
        actions: [
          if (haySinLeer)
            TextButton(
              onPressed: () async {
                try {
                  await ref.read(notificacionesRepositoryProvider).marcarTodas();
                  ref.invalidate(notificacionesProvider);
                  ref.invalidate(sinLeerProvider);
                } on NotificacionesFailure catch (e) {
                  if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
                }
              },
              child: const Text('Marcar todas como leídas'),
            ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(notificacionesProvider.future),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                const _ActivarPush(),
                ...switch (lista) {
                  AsyncValue(value: final List<Notificacion> ns) when ns.isEmpty => [
                      const SizedBox(height: 48),
                      const Aviso(
                        icono: Icons.notifications_none,
                        texto: 'No tenés notificaciones',
                        detalle: 'Acá te avisamos cuando te mencionen, te asignen una tarea o tu docente mande un aviso.',
                      ),
                    ],
                  AsyncValue(value: final List<Notificacion> ns) => [for (final n in ns) _Fila(n: n, onTap: () => _abrir(context, ref, n))],
                  AsyncValue(hasError: true) => [
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('No pudimos traer las notificaciones. Probá de nuevo', textAlign: TextAlign.center),
                      ),
                    ],
                  _ => [const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))],
                },
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.n, required this.onTap});
  final Notificacion n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: n.leida ? Colors.transparent : scheme.primaryContainer.withValues(alpha: 0.35),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: n.leida ? scheme.surfaceContainerHighest : scheme.primaryContainer,
          child: Icon(n.tipo.icono, color: n.leida ? scheme.onSurfaceVariant : scheme.onPrimaryContainer, size: 20),
        ),
        title: Text(n.titulo, style: n.leida ? null : const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          [?n.cuerpo, formatearFecha(n.createdAt, DateTime.now())].join('\n'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: n.cuerpo != null,
        trailing: n.leida
            ? null
            : Semantics(label: 'Sin leer', child: Icon(Icons.circle, size: 10, color: scheme.primary)),
      ),
    );
  }
}

/// Invitación a activar el push en este dispositivo (en la web, el navegador
/// solo deja pedir permiso desde un toque).
class _ActivarPush extends ConsumerWidget {
  const _ActivarPush();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(estadoPushProvider).value;
    if (estado == null || estado == EstadoPush.activo || estado == EstadoPush.noConfigurado) {
      return const SizedBox.shrink();
    }
    final bloqueado = estado == EstadoPush.bloqueado;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: ListTile(
        leading: Icon(bloqueado ? Icons.notifications_off_outlined : Icons.notifications_active_outlined),
        title: Text(bloqueado
            ? 'Las notificaciones están bloqueadas'
            : 'Recibí los avisos aunque la app esté cerrada'),
        subtitle: Text(bloqueado
            ? (kIsWeb
                ? 'Habilitalas en la configuración del sitio de tu navegador (el candado al lado de la dirección).'
                : 'Habilitalas en Ajustes → Apps → StudyVerse → Notificaciones.')
            : 'Menciones, tareas asignadas, avisos de tu docente y más.'),
        trailing: bloqueado
            ? null
            : FilledButton(
                onPressed: () async {
                  final r = await ref.read(pushProvider).activar().catchError((_) => EstadoPush.sinPedir);
                  ref.invalidate(estadoPushProvider);
                  if (!context.mounted) return;
                  mostrarMensaje(context, switch (r) {
                    EstadoPush.activo => 'Listo: te vamos a avisar en este dispositivo',
                    EstadoPush.bloqueado => kIsWeb
                        ? 'Las bloqueaste: podés habilitarlas desde el navegador'
                        : 'Las bloqueaste: podés habilitarlas en los ajustes del teléfono',
                    _ => 'No se activaron. Probá de nuevo',
                  });
                },
                child: const Text('Activar'),
              ),
      ),
    );
  }
}
