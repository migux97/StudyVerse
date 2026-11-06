import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/web/guardar_archivo.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../cursos/domain/curso.dart';
import '../../cursos/presentation/cursos_providers.dart';
import '../../files/domain/file_item.dart' show nombreVisible;
import '../../groups/presentation/group_shell.dart' show Aviso;
import '../domain/trabajo.dart';
import 'entregas_providers.dart';
import 'entregas_widgets.dart';

/// Pestaña "Trabajos" del curso: los TPs con cuántos grupos entregaron.
class TrabajosDelCurso extends ConsumerWidget {
  const TrabajosDelCurso({super.key, required this.curso});
  final Curso curso;

  Future<void> _nuevo(BuildContext context, WidgetRef ref) async {
    final d = await pedirTrabajo(context);
    if (d == null || !context.mounted) return;
    try {
      await ref.read(entregasRepositoryProvider).crear(
            cursoId: curso.id,
            titulo: d.titulo,
            consigna: d.consigna,
            venceAt: d.venceAt,
            notaMaxima: d.notaMaxima,
          );
      ref.invalidate(trabajosProvider(curso.id));
      if (context.mounted) mostrarMensaje(context, 'Creamos «${d.titulo}» y les avisamos a los grupos');
    } on EntregasFailure catch (e) {
      if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trabajos = ref.watch(trabajosProvider(curso.id));
    final entregas = ref.watch(entregasDelCursoProvider(curso.id)).value ?? const <Entrega>[];
    final cantidadGrupos = ref.watch(gruposDelCursoProvider(curso.id)).value?.length ?? curso.cantidadGrupos;
    final theme = Theme.of(context);
    final ahora = DateTime.now();

    final boton = FilledButton.icon(
      icon: const Icon(Icons.add),
      label: const Text('Nuevo trabajo'),
      onPressed: () => _nuevo(context, ref),
    );

    return switch (trabajos) {
      AsyncValue(:final error?) => Aviso(
          icono: Icons.cloud_off_outlined,
          texto: error is EntregasFailure ? error.mensaje : 'Algo salió mal. Probá de nuevo',
          accion: FilledButton(onPressed: () => ref.invalidate(trabajosProvider(curso.id)), child: const Text('Reintentar')),
        ),
      AsyncValue(value: final List<Trabajo> ts) when ts.isEmpty => Aviso(
          icono: Icons.assignment_outlined,
          texto: 'Todavía no hay trabajos',
          detalle: 'Creá un trabajo con su consigna y fecha de entrega: les llega a todos los grupos y cada uno '
              'entrega su archivo desde la app.',
          accion: boton,
        ),
      AsyncValue(value: final List<Trabajo> ts) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            Align(alignment: Alignment.centerRight, child: boton),
            const SizedBox(height: 8),
            for (final t in ts)
              Builder(builder: (context) {
                final deEste = entregas.where((e) => e.trabajoId == t.id).toList();
                final porCorregir = deEste.where((e) => e.estado == EstadoEntrega.entregada).length;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                    leading: Icon(Icons.assignment_outlined, color: theme.colorScheme.primary),
                    title: Text(t.titulo),
                    subtitle: Text([
                      '${t.vencido(ahora) ? 'Venció' : 'Vence'} el ${formatearVencimiento(t.venceAt)}',
                      '${deEste.length} de $cantidadGrupos ${cantidadGrupos == 1 ? 'grupo entregó' : 'grupos entregaron'}',
                    ].join(' · ')),
                    trailing: porCorregir == 0
                        ? const Icon(Icons.chevron_right)
                        : Badge.count(count: porCorregir, child: const Icon(Icons.rate_review_outlined)),
                    onTap: () => context.push(Routes.trabajo(curso.id, t.id)),
                  ),
                );
              }),
          ],
        ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

/// Un trabajo (docente): la consigna y la entrega de cada grupo, para corregir.
class TrabajoScreen extends ConsumerWidget {
  const TrabajoScreen({super.key, required this.cursoId, required this.trabajoId});
  final String cursoId;
  final String trabajoId;

  Future<void> _editar(BuildContext context, WidgetRef ref, Trabajo t) async {
    final d = await pedirTrabajo(context, inicial: t);
    if (d == null || !context.mounted) return;
    try {
      await ref
          .read(entregasRepositoryProvider)
          .editar(t, titulo: d.titulo, consigna: d.consigna, venceAt: d.venceAt, notaMaxima: d.notaMaxima);
      ref.invalidate(trabajoProvider(trabajoId));
      ref.invalidate(trabajosProvider(cursoId));
    } on EntregasFailure catch (e) {
      if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  Future<void> _borrar(BuildContext context, WidgetRef ref, Trabajo t) async {
    final ok = await confirmar(
      context,
      titulo: '¿Eliminar «${t.titulo}»?',
      mensaje: 'Se borran también las entregas y las notas de este trabajo. Los archivos de los grupos no se tocan.',
      accion: 'Eliminar',
      peligroso: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(entregasRepositoryProvider).borrar(t.id);
      ref.invalidate(trabajosProvider(cursoId));
      if (context.mounted) context.canPop() ? context.pop() : context.go(Routes.curso(cursoId));
    } on EntregasFailure catch (e) {
      if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trabajo = ref.watch(trabajoProvider(trabajoId));
    final t = trabajo.value;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.curso(cursoId))),
        title: Text(t?.titulo ?? 'Trabajo'),
        actions: [
          if (t != null)
            PopupMenuButton<String>(
              tooltip: 'Más opciones',
              onSelected: (op) => op == 'editar' ? _editar(context, ref, t) : _borrar(context, ref, t),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'editar', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Editar'))),
                PopupMenuItem(value: 'borrar', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Eliminar trabajo'))),
              ],
            ),
        ],
      ),
      body: switch (trabajo) {
        AsyncValue(:final error?) => Aviso(
            icono: Icons.assignment_outlined,
            texto: error is EntregasFailure ? error.mensaje : 'Algo salió mal. Probá de nuevo',
            accion: FilledButton(onPressed: () => ref.invalidate(trabajoProvider(trabajoId)), child: const Text('Reintentar')),
          ),
        AsyncValue(value: final Trabajo t) => _Detalle(cursoId: cursoId, trabajo: t),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Detalle extends ConsumerWidget {
  const _Detalle({required this.cursoId, required this.trabajo});
  final String cursoId;
  final Trabajo trabajo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = trabajo;
    final grupos = ref.watch(gruposDelCursoProvider(cursoId)).value ?? const <GrupoDelCurso>[];
    final entregas = {
      for (final e in ref.watch(entregasDelCursoProvider(cursoId)).value ?? const <Entrega>[])
        if (e.trabajoId == t.id) e.groupId: e,
    };
    final ahora = DateTime.now();
    // Primero lo que falta corregir, después lo corregido y al final quien no entregó.
    int orden(GrupoDelCurso g) => switch (entregas[g.id]?.estado) {
          EstadoEntrega.entregada => 0,
          null => 2,
          _ => 1,
        };
    final ordenados = [...grupos]..sort((a, b) {
        final o = orden(a).compareTo(orden(b));
        return o != 0 ? o : a.nombre.compareTo(b.nombre);
      });

    return RefreshIndicator(
      onRefresh: () => ref.refresh(entregasDelCursoProvider(cursoId).future),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        '${t.vencido(ahora) ? 'Venció' : 'Vence'} el ${formatearVencimiento(t.venceAt)} · '
                        'nota máxima ${formatearNota(t.notaMaxima)}',
                        style: theme.textTheme.labelLarge,
                      ),
                      if (t.consigna != null) ...[
                        const SizedBox(height: 8),
                        SelectableText(t.consigna!),
                      ],
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Entregas · ${entregas.length} de ${grupos.length}', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final g in ordenados) _FilaEntrega(trabajo: t, grupo: g, entrega: entregas[g.id], cursoId: cursoId),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilaEntrega extends ConsumerWidget {
  const _FilaEntrega({required this.trabajo, required this.grupo, required this.entrega, required this.cursoId});
  final Trabajo trabajo;
  final GrupoDelCurso grupo;
  final Entrega? entrega;
  final String cursoId;

  Future<void> _corregir(BuildContext context, WidgetRef ref, Entrega e) async {
    final c = await pedirCorreccion(context, trabajo: trabajo, entrega: e, grupo: grupo.nombre);
    if (c == null || !context.mounted) return;
    try {
      await ref.read(entregasRepositoryProvider).corregir(e.id, estado: c.estado, nota: c.nota, devolucion: c.devolucion);
      ref.invalidate(entregasDelCursoProvider(cursoId));
      if (context.mounted) mostrarMensaje(context, 'Guardamos la corrección y le avisamos al grupo');
    } on EntregasFailure catch (err) {
      if (context.mounted) mostrarMensaje(context, err.mensaje, error: true);
    }
  }

  Future<void> _descargar(BuildContext context, WidgetRef ref, Entrega e) async {
    try {
      final bytes = await ref.read(entregasRepositoryProvider).bytesDeLaVersion(e.fileId, e.versionNumber);
      final nombre = e.archivoNombre ?? 'Entrega';
      await guardarEnDispositivo(Uint8List.fromList(bytes), nombre, 'application/octet-stream');
    } on EntregasFailure catch (err) {
      if (context.mounted) mostrarMensaje(context, err.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final e = entrega;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(grupo.nombre, style: theme.textTheme.titleMedium),
            ChipEstado(estado: e?.estado ?? EstadoEntrega.pendiente, nota: e?.nota, tarde: e != null && e.tarde(trabajo)),
          ]),
          if (e == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('Todavía no entregó', style: theme.textTheme.bodySmall),
            )
          else ...[
            const SizedBox(height: 6),
            Text(
              '${nombreVisible(e.archivoNombre ?? 'Archivo')} · v${e.versionNumber} · '
              '${e.entregadaPor ?? 'Alguien'} el ${formatearVencimiento(e.entregadaAt)}',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (e.devolucion != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Devolución: ${e.devolucion}', maxLines: 3, overflow: TextOverflow.ellipsis),
              ),
            const SizedBox(height: 4),
            Wrap(spacing: 4, children: [
              FilledButton.tonalIcon(
                icon: const Icon(Icons.rate_review_outlined, size: 18),
                label: Text(e.estado.corregida ? 'Cambiar corrección' : 'Corregir'),
                onPressed: () => _corregir(context, ref, e),
              ),
              TextButton.icon(
                icon: const Icon(Icons.history, size: 18),
                label: const Text('Ver versiones'),
                onPressed: () => context.push(Routes.historial(e.groupId, e.fileId)),
              ),
              TextButton.icon(
                icon: const Icon(Icons.download_outlined, size: 18),
                label: Text('Descargar v${e.versionNumber}'),
                onPressed: () => _descargar(context, ref, e),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}
