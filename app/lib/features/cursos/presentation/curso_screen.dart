import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/forms/validar.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/auth_layout.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/text_input_dialog.dart';
import '../../groups/presentation/group_shell.dart' show Aviso;
import '../domain/curso.dart';
import 'cursos_providers.dart';
import 'inicio_docente.dart';
import '../../avisos/domain/aviso.dart';
import '../../avisos/presentation/avisos_providers.dart';
import '../../avisos/presentation/avisos_widgets.dart';

/// Un curso del docente: su código y los grupos que se sumaron.
class CursoScreen extends ConsumerWidget {
  const CursoScreen({super.key, required this.cursoId});
  final String cursoId;

  Future<void> _intentar(BuildContext context, Future<void> Function() accion) async {
    try {
      await accion();
    } on CursosFailure catch (e) {
      if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final curso = ref.watch(cursoProvider(cursoId));
    final grupos = ref.watch(gruposDelCursoProvider(cursoId));
    final c = curso.value;

    return Scaffold(
      appBar: AppBar(
        // Abierto desde un link no hay pantalla anterior: vuelve a Mis cursos.
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.grupos)),
        title: Text(c?.nombre ?? 'Curso'),
        actions: [
          if (c != null)
            PopupMenuButton<String>(
              tooltip: 'Más opciones',
              onSelected: (op) async {
                switch (op) {
                  case 'nombre':
                    final nombre = await pedirTexto(
                      context,
                      titulo: 'Cambiar nombre',
                      etiqueta: 'Nombre del curso',
                      inicial: c.nombre,
                      accion: 'Guardar',
                      maximo: 120,
                      validator: Validar.texto(vacio: 'Ingresá el nombre del curso', max: 120),
                    );
                    if (nombre == null || nombre == c.nombre || !context.mounted) return;
                    await _intentar(context, () async {
                      await ref.read(cursosRepositoryProvider).renombrar(c.id, nombre);
                      ref.invalidate(cursoProvider(cursoId));
                      ref.invalidate(misCursosProvider);
                    });
                  case 'borrar':
                    final ok = await confirmar(
                      context,
                      titulo: '¿Eliminar "${c.nombre}"?',
                      mensaje: 'Los grupos no se borran: siguen igual, pero vas a dejar de verlos.',
                      accion: 'Eliminar',
                      peligroso: true,
                    );
                    if (!ok || !context.mounted) return;
                    await _intentar(context, () async {
                      await ref.read(cursosRepositoryProvider).borrar(c.id);
                      ref.invalidate(misCursosProvider);
                      if (context.mounted) context.go(Routes.grupos);
                    });
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'nombre', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Cambiar nombre'))),
                PopupMenuItem(value: 'borrar', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Eliminar curso'))),
              ],
            ),
        ],
      ),
      body: switch (curso) {
        AsyncValue(:final error?) => Aviso(
            icono: Icons.school_outlined,
            texto: error is CursosFailure ? error.mensaje : 'Algo salió mal. Probá de nuevo',
            accion: FilledButton(onPressed: () => ref.invalidate(cursoProvider(cursoId)), child: const Text('Reintentar')),
          ),
        AsyncValue(value: final Curso c) => RefreshIndicator(
            onRefresh: () {
              ref.invalidate(avisosDelCursoProvider(cursoId));
              return ref.refresh(gruposDelCursoProvider(cursoId).future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _CodigoCard(
                        curso: c,
                        onRegenerar: () async {
                          final ok = await confirmar(
                            context,
                            titulo: '¿Generar un código nuevo?',
                            mensaje: 'El código actual deja de servir. Los grupos que ya se sumaron siguen en el curso.',
                            accion: 'Generar',
                          );
                          if (!ok || !context.mounted) return;
                          await _intentar(context, () async {
                            await ref.read(cursosRepositoryProvider).regenerarCodigo(c.id);
                            ref.invalidate(cursoProvider(cursoId));
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      _AvisosDelCurso(curso: c, grupos: grupos.value ?? const []),
                      const SizedBox(height: 16),
                      ...switch (grupos) {
                        AsyncValue(value: final List<GrupoDelCurso> gs) when gs.isEmpty => [
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Todavía no se sumó ningún grupo. Cuando el admin de un grupo use el código, '
                                'lo vas a ver acá.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        AsyncValue(value: final List<GrupoDelCurso> gs) => [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                              child: Text('Grupos · ${gs.length}', style: Theme.of(context).textTheme.titleSmall),
                            ),
                            for (final g in gs) _GrupoCard(grupo: g),
                          ],
                        AsyncValue(hasError: true) => [
                            const Padding(padding: EdgeInsets.all(24), child: Text('No pudimos traer los grupos. Probá de nuevo')),
                          ],
                        _ => [const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))],
                      },
                    ]),
                  ),
                ),
              ],
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _CodigoCard extends StatelessWidget {
  const _CodigoCard({required this.curso, required this.onRegenerar});
  final Curso curso;
  final VoidCallback onRegenerar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Código del curso', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          SelectableText(curso.codigoVisible,
              style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 2, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            'Pasáselo a tu clase. El admin de cada grupo lo carga en "Más opciones → Sumar a un curso".',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copiar'),
              onPressed: () => copiarCodigo(context, curso),
            ),
            TextButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Generar otro'),
              onPressed: onRegenerar,
            ),
          ]),
        ]),
      ),
    );
  }
}

class _GrupoCard extends StatelessWidget {
  const _GrupoCard({required this.grupo});
  final GrupoDelCurso grupo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final g = grupo;
    final progreso = g.tareasTotal == 0 ? null : g.tareasHechas / g.tareasTotal;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(Routes.grupo(g.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.folder_rounded, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(g.nombre, style: theme.textTheme.titleMedium)),
              if (g.entregadas > 0)
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.outbox_outlined, size: 16),
                  label: Text(g.entregadas == 1 ? '1 entregada' : '${g.entregadas} entregadas'),
                ),
            ]),
            const SizedBox(height: 6),
            Text(
              g.integrantes.isEmpty ? 'Sin integrantes' : g.integrantes.join(', '),
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (g.materias.isNotEmpty)
              Text(g.materias.join(' · '), style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            if (progreso == null)
              Text('Todavía no cargaron tareas', style: theme.textTheme.bodySmall)
            else ...[
              LinearProgressIndicator(value: progreso, borderRadius: BorderRadius.circular(4)),
              const SizedBox(height: 4),
              Text('${g.tareasHechas} de ${g.tareasTotal} tareas hechas', style: theme.textTheme.bodySmall),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Avisos del curso: mandar uno (a todos o a un grupo) y ver los anteriores.
class _AvisosDelCurso extends ConsumerWidget {
  const _AvisosDelCurso({required this.curso, required this.grupos});
  final Curso curso;
  final List<GrupoDelCurso> grupos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final nombres = {for (final g in grupos) g.id: g.nombre};
    final avisos = [
      for (final a in ref.watch(avisosDelCursoProvider(curso.id)).value ?? const <AvisoDocente>[])
        a.conGrupo(a.groupId == null ? null : nombres[a.groupId]),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('Avisos', style: theme.textTheme.titleSmall),
            FilledButton.icon(
              icon: const Icon(Icons.campaign_outlined, size: 18),
              label: const Text('Mandar un aviso'),
              onPressed: () => mandarAviso(
                context,
                ref,
                cursoId: curso.id,
                grupos: [for (final g in grupos) (id: g.id, nombre: g.nombre)],
              ),
            ),
          ]),
          if (avisos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Mandá avisos a todo el curso o a un grupo: les llegan al instante.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            )
          else
            ListaAvisos(
              avisos: avisos.take(5).toList(),
              onBorrar: (a) async {
                final ok = await confirmar(context,
                    titulo: '¿Borrar el aviso?', mensaje: a.texto, accion: 'Borrar', peligroso: true);
                if (!ok || !context.mounted) return;
                try {
                  await ref.read(avisosRepositoryProvider).borrar(a.id);
                  ref.invalidate(avisosDelCursoProvider(curso.id));
                } on AvisosFailure catch (e) {
                  if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
                }
              },
            ),
        ]),
      ),
    );
  }
}
