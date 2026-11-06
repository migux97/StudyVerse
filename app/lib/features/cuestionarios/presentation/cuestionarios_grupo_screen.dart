import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../entregas/domain/trabajo.dart' show formatearNota, formatearVencimiento;
import '../../groups/presentation/group_shell.dart' show Aviso, GroupLoader;
import '../domain/cuestionario.dart';
import 'cuestionarios_providers.dart';

/// Los cuestionarios del curso del grupo (cada alumno rinde el suyo).
class CuestionariosGrupoScreen extends StatelessWidget {
  const CuestionariosGrupoScreen({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context) => GroupLoader(
        groupId: groupId,
        builder: (g) => Scaffold(
          appBar: AppBar(
            leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.grupo(groupId))),
            title: const Text('Cuestionarios'),
          ),
          body: g.cursoId == null
              ? const Aviso(
                  icono: Icons.school_outlined,
                  texto: 'El grupo no está en un curso',
                  detalle: 'Cuando el admin lo sume con el código del docente, acá vas a ver los cuestionarios.',
                )
              : _Lista(groupId: groupId),
        ),
      );
}

class _Lista extends ConsumerWidget {
  const _Lista({required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lista = ref.watch(cuestionariosDelGrupoProvider(groupId));
    final ahora = DateTime.now();
    return switch (lista) {
      AsyncValue(:final error?) => Aviso(
          icono: Icons.cloud_off_outlined,
          texto: error is CuestionariosFailure ? error.mensaje : 'Algo salió mal. Probá de nuevo',
          accion: FilledButton(
              onPressed: () => ref.invalidate(cuestionariosDelGrupoProvider(groupId)), child: const Text('Reintentar')),
        ),
      AsyncValue(value: final List<Cuestionario> cs) when cs.isEmpty => const Aviso(
          icono: Icons.quiz_outlined,
          texto: 'Todavía no hay cuestionarios',
          detalle: 'Cuando tu docente publique uno, te llega un aviso y lo rendís desde acá.',
        ),
      AsyncValue(value: final List<Cuestionario> cs) => RefreshIndicator(
          onRefresh: () => ref.refresh(cuestionariosDelGrupoProvider(groupId).future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(children: [
                    for (final c in cs)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            c.estado(ahora) == EstadoCuestionario.abierto ? Icons.quiz : Icons.quiz_outlined,
                            color: c.estado(ahora) == EstadoCuestionario.abierto
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          title: Text(c.titulo),
                          subtitle: Text(ventana(c, ahora)),
                          trailing: Chip(visualDensity: VisualDensity.compact, label: Text(c.estado(ahora).texto)),
                          onTap: () => context.push(Routes.cuestionarioAlumno(groupId, c.id)),
                        ),
                      ),
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

/// "Abre el lun 10/11 08:00", "Cierra el vie 14/11 23:59", "Cerró el…".
String formatearCierre(Cuestionario c, DateTime ahora) => switch (c.estado(ahora)) {
      EstadoCuestionario.programado => 'Abre el ${formatearVencimiento(c.abreAt)}',
      EstadoCuestionario.cerrado => 'Cerró el ${formatearVencimiento(c.cierraAt)}',
      _ => 'Cierra el ${formatearVencimiento(c.cierraAt)}',
    };

/// Lo anterior más el tiempo y los intentos: "Cierra el vie 14/11 23:59 · 40 min".
String ventana(Cuestionario c, DateTime ahora) {
  final partes = [
    formatearCierre(c, ahora),
    if (c.duracionMin case final m?) '$m min',
    if (c.intentos > 1) '${c.intentos} intentos',
  ];
  return partes.join(' · ');
}

/// Un cuestionario para el alumno: las reglas, sus intentos y el botón para
/// empezar (o seguir).
class CuestionarioAlumnoScreen extends ConsumerWidget {
  const CuestionarioAlumnoScreen({super.key, required this.groupId, required this.cuestionarioId});
  final String groupId;
  final String cuestionarioId;

  Future<void> _empezar(BuildContext context, WidgetRef ref, Cuestionario c, {required bool seguir}) async {
    if (!seguir) {
      final ok = await confirmar(
        context,
        titulo: '¿Empezar «${c.titulo}»?',
        mensaje: [
          if (c.duracionMin case final m?) 'Tenés $m minutos desde que empezás.' else 'Tenés hasta que cierre.',
          'Mientras rendís, si salís de la pantalla (otra pestaña, otra app o la pantalla de inicio) queda '
              'registrado y lo ve tu docente.',
          if (c.topeSalidas != null) textoTope(c.topeSalidas),
        ].join(' '),
        accion: 'Empezar',
      );
      if (!ok || !context.mounted) return;
    }
    try {
      final id = await ref.read(cuestionariosRepositoryProvider).empezar(c.id);
      if (!context.mounted) return;
      ref.invalidate(misIntentosProvider(c.id));
      context.push(Routes.rendir(groupId, c.id, id));
    } on CuestionariosFailure catch (e) {
      if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cuestionario = ref.watch(cuestionarioProvider(cuestionarioId));
    final intentos = ref.watch(misIntentosProvider(cuestionarioId));
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ahora = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
            onPressed: () => context.canPop() ? context.pop() : context.go(Routes.cuestionariosGrupo(groupId))),
        title: Text(cuestionario.value?.titulo ?? 'Cuestionario'),
      ),
      body: switch ((cuestionario, intentos)) {
        (AsyncValue(:final error?), _) || (_, AsyncValue(:final error?)) => Aviso(
            icono: Icons.cloud_off_outlined,
            texto: error is CuestionariosFailure ? error.mensaje : 'Algo salió mal. Probá de nuevo',
            accion: FilledButton(
              onPressed: () {
                ref.invalidate(cuestionarioProvider(cuestionarioId));
                ref.invalidate(misIntentosProvider(cuestionarioId));
              },
              child: const Text('Reintentar'),
            ),
          ),
        (AsyncValue(value: final Cuestionario c), AsyncValue(value: final List<Intento> mios)) => Builder(builder: (_) {
            final enCurso = mios.where((i) => !i.entregado).firstOrNull;
            final estado = c.estado(ahora);
            final quedan = c.intentos - mios.length;
            final boton = switch (estado) {
              _ when enCurso != null => FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Seguir'),
                  onPressed: () => _empezar(context, ref, c, seguir: true),
                ),
              EstadoCuestionario.abierto when quedan > 0 => FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: Text(mios.isEmpty ? 'Empezar' : 'Volver a intentar'),
                  onPressed: () => _empezar(context, ref, c, seguir: false),
                ),
              _ => null,
            };
            return RefreshIndicator(
              onRefresh: () {
                ref.invalidate(cuestionarioProvider(cuestionarioId));
                return ref.refresh(misIntentosProvider(cuestionarioId).future);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(ventana(c, ahora), style: theme.textTheme.bodyMedium),
                              if (c.descripcion case final d?) ...[
                                const SizedBox(height: 8),
                                Text(d),
                              ],
                              const SizedBox(height: 12),
                              _Regla(Icons.timer_outlined,
                                  c.duracionMin == null ? 'Sin tiempo límite: hasta que cierre' : '${c.duracionMin} minutos para rendir'),
                              _Regla(Icons.replay, c.intentos == 1 ? 'Un solo intento' : '${c.intentos} intentos (cuenta la mejor nota)'),
                              _Regla(
                                Icons.visibility_outlined,
                                [
                                  'Si salís de la pantalla mientras rendís, queda registrado.',
                                  if (c.topeSalidas != null) textoTope(c.topeSalidas),
                                ].join(' '),
                              ),
                              _Regla(Icons.grading_outlined,
                                  c.resultadosAlCerrar ? 'La nota se ve cuando cierra' : 'La nota se ve al entregar'),
                              if (boton != null) ...[
                                const SizedBox(height: 12),
                                Align(alignment: Alignment.centerRight, child: boton),
                              ] else if (estado == EstadoCuestionario.abierto && quedan <= 0) ...[
                                const SizedBox(height: 8),
                                Text('Ya usaste todos tus intentos',
                                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                              ],
                            ]),
                          ),
                        ),
                        if (mios.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                            child: Text('Tus intentos', style: theme.textTheme.titleSmall),
                          ),
                          for (final i in mios.reversed)
                            Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(child: Text('${i.numero}')),
                                title: Text(!i.entregado
                                    ? 'Rindiendo ahora'
                                    : !i.visible
                                        ? 'Entregado · la nota se ve cuando cierre'
                                        : i.pendiente
                                            ? 'Entregado · falta que corrijan el desarrollo'
                                            : textoNota(i, c)),
                                subtitle: Text([
                                  estadoIntento(i),
                                  if (i.salidas > 0) textoSalidas(i.salidas),
                                  if (i.visible && i.puntajeMax != null)
                                    '${formatearNota(i.puntaje ?? 0)} de ${formatearNota(i.puntajeMax!)} puntos',
                                ].join(' · ')),
                                trailing: i.entregado ? const Icon(Icons.chevron_right) : null,
                                onTap: !i.entregado
                                    ? null
                                    : () => context.push(Routes.resultadoIntento(groupId, c.id, i.id)),
                              ),
                            ),
                        ],
                      ]),
                    ),
                  ),
                ],
              ),
            );
          }),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Regla extends StatelessWidget {
  const _Regla(this.icono, this.texto);
  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icono, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(child: Text(texto)),
      ]),
    );
  }
}
