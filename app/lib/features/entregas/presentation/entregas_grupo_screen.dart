import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../chat/presentation/chat_providers.dart' show chatRepositoryProvider;
import '../../chat/domain/mensaje.dart' show ChatFailure;
import '../../files/domain/file_item.dart' show fileKindFor, nombreVisible;
import '../../files/presentation/file_icon.dart';
import '../../groups/domain/group.dart';
import '../../groups/presentation/group_shell.dart' show Aviso, GroupLoader;
import '../domain/trabajo.dart';
import 'entregas_providers.dart';
import 'entregas_widgets.dart';

/// Los trabajos del curso y lo que entregó el grupo (con la nota y la devolución).
class EntregasGrupoScreen extends StatelessWidget {
  const EntregasGrupoScreen({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context) => GroupLoader(
        groupId: groupId,
        builder: (g) => Scaffold(
          appBar: AppBar(
            leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.grupo(groupId))),
            title: const Text('Trabajos del curso'),
          ),
          body: g.cursoId == null
              ? const Aviso(
                  icono: Icons.school_outlined,
                  texto: 'El grupo no está en un curso',
                  detalle: 'Cuando el admin lo sume con el código del docente, acá vas a ver los trabajos para entregar.',
                )
              : _Lista(grupo: g),
        ),
      );
}

class _Lista extends ConsumerWidget {
  const _Lista({required this.grupo});
  final Group grupo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trabajos = ref.watch(trabajosDelGrupoProvider(grupo.id));
    final entregas = ref.watch(entregasDelGrupoProvider(grupo.id)).value ?? const <String, Entrega>{};
    return switch (trabajos) {
      AsyncValue(:final error?) => Aviso(
          icono: Icons.cloud_off_outlined,
          texto: error is EntregasFailure ? error.mensaje : 'Algo salió mal. Probá de nuevo',
          accion: FilledButton(
              onPressed: () => ref.invalidate(trabajosDelGrupoProvider(grupo.id)), child: const Text('Reintentar')),
        ),
      AsyncValue(value: final List<Trabajo> ts) when ts.isEmpty => const Aviso(
          icono: Icons.assignment_outlined,
          texto: 'Todavía no hay trabajos',
          detalle: 'Cuando tu docente publique uno, te llega un aviso y lo entregás desde acá.',
        ),
      AsyncValue(value: final List<Trabajo> ts) => RefreshIndicator(
          onRefresh: () {
            ref.invalidate(entregasDelGrupoProvider(grupo.id));
            return ref.refresh(trabajosDelGrupoProvider(grupo.id).future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (final t in ts) _TarjetaTrabajo(grupo: grupo, trabajo: t, entrega: entregas[t.id]),
                  ]),
                ),
              ),
            ],
          ),
        ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _TarjetaTrabajo extends ConsumerWidget {
  const _TarjetaTrabajo({required this.grupo, required this.trabajo, required this.entrega});
  final Group grupo;
  final Trabajo trabajo;
  final Entrega? entrega;

  Future<void> _entregar(BuildContext context, WidgetRef ref) async {
    final List<({String id, String nombre})> archivos;
    try {
      archivos = await ref.read(chatRepositoryProvider).archivos(grupo.id);
    } on ChatFailure catch (e) {
      if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
      return;
    }
    if (!context.mounted) return;
    if (archivos.isEmpty) return mostrarMensaje(context, 'Primero subí el archivo al grupo');
    final elegido = await showModalBottomSheet<({String id, String nombre})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              title: Text('¿Qué archivo entregan para ${trabajo.titulo}?'),
              subtitle: const Text('Se entrega la versión que tiene ahora'),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final a in archivos)
                  ListTile(
                    leading: FileIcon(kind: fileKindFor(a.nombre)),
                    title: Text(nombreVisible(a.nombre), overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(ctx, a),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
    if (elegido == null || !context.mounted) return;
    final ok = await confirmar(
      context,
      titulo: '¿Entregar ${nombreVisible(elegido.nombre)}?',
      mensaje: 'Se entrega la versión actual. Pueden seguir subiendo cambios: lo entregado no cambia. '
          'Mientras no lo corrijan, pueden cambiar la entrega.',
      accion: 'Entregar',
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(entregasRepositoryProvider).entregar(trabajoId: trabajo.id, groupId: grupo.id, fileId: elegido.id);
      ref.invalidate(entregasDelGrupoProvider(grupo.id));
      if (context.mounted) mostrarMensaje(context, 'Entregaron «${trabajo.titulo}»');
    } on EntregasFailure catch (e) {
      if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final t = trabajo;
    final e = entrega;
    final ahora = DateTime.now();
    final puedeEntregar = !grupo.soloLectura && (e == null || e.sePuedeCambiar);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(t.titulo, style: theme.textTheme.titleMedium),
            ChipEstado(estado: e?.estado ?? EstadoEntrega.pendiente, nota: e?.nota, tarde: e != null && e.tarde(t)),
          ]),
          const SizedBox(height: 4),
          Text(
            '${t.vencido(ahora) ? 'Venció' : 'Vence'} el ${formatearVencimiento(t.venceAt)} · nota máxima ${formatearNota(t.notaMaxima)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: e == null && t.vencido(ahora) ? scheme.error : scheme.onSurfaceVariant,
            ),
          ),
          if (t.consigna != null) ...[
            const SizedBox(height: 8),
            Text(t.consigna!),
          ],
          if (e != null) ...[
            const Divider(height: 24),
            Text(
              'Entregaron ${nombreVisible(e.archivoNombre ?? 'Archivo')} (v${e.versionNumber}) · '
              '${e.entregadaPor ?? 'Alguien'}, ${formatearVencimiento(e.entregadaAt)}',
              style: theme.textTheme.bodyMedium,
            ),
            if (e.devolucion != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.estado == EstadoEntrega.entregada ? 'Devolución anterior' : 'Devolución',
                      style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  SelectableText(e.devolucion!),
                ]),
              ),
            ],
          ],
          if (puedeEntregar) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.outbox_outlined, size: 18),
              label: Text(e == null
                  ? 'Entregar'
                  : e.estado == EstadoEntrega.aRehacer
                      ? 'Volver a entregar'
                      : 'Cambiar la entrega'),
              onPressed: () => _entregar(context, ref),
            ),
          ],
        ]),
      ),
    );
  }
}
