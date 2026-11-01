import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/domain/profile.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/presentation/user_avatar.dart';
import '../../files/domain/file_item.dart';
import '../../groups/domain/group.dart';
import '../../groups/presentation/group_shell.dart';
import '../domain/task.dart';
import 'tasks_providers.dart';

/// "Aportes": cuántas tareas completó y cuántas versiones subió cada integrante.
class ContributionsScreen extends StatelessWidget {
  const ContributionsScreen({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context) =>
      GroupLoader(groupId: groupId, builder: (g) => _Aportes(grupo: g));
}

class _Aportes extends ConsumerWidget {
  const _Aportes({required this.grupo});
  final Group grupo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aportes = ref.watch(contributionsProvider(grupo.id));
    final miId = ref.watch(authStateProvider).value?.id;
    final theme = Theme.of(context);

    return GroupShell(
      grupo: grupo,
      seccion: SeccionGrupo.aportes,
      body: aportes.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Aviso(icono: Icons.error_outline, texto: e.toString()),
        data: (lista) {
          // Las barras son relativas a quien más aportó en cada cosa.
          final maxTareas = lista.fold(0, (m, a) => a.tareasCompletadas > m ? a.tareasCompletadas : m);
          final maxVersiones = lista.fold(0, (m, a) => a.versionesSubidas > m ? a.versionesSubidas : m);
          final ordenados = [...lista]..sort((a, b) =>
              (b.tareasCompletadas + b.versionesSubidas).compareTo(a.tareasCompletadas + a.versionesSubidas));

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
                    child: Text(
                      'Tareas que cada uno completó y versiones de archivos que subió en este grupo.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  for (final a in ordenados)
                    _AporteCard(
                      aporte: a,
                      esYo: a.userId == miId,
                      maxTareas: maxTareas,
                      maxVersiones: maxVersiones,
                    ),
                  const SizedBox(height: 16),
                  // Estructura lista para el plan premium (todavía no implementado).
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.picture_as_pdf_outlined),
                      title: const Text('Reporte de aportes en PDF'),
                      subtitle: const Text('Disponible con el plan premium del grupo'),
                      trailing: Chip(
                        label: const Text('Premium'),
                        backgroundColor: theme.colorScheme.tertiaryContainer,
                        side: BorderSide.none,
                      ),
                      enabled: false,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AporteCard extends StatelessWidget {
  const _AporteCard({
    required this.aporte,
    required this.esYo,
    required this.maxTareas,
    required this.maxVersiones,
  });

  final Aporte aporte;
  final bool esYo;
  final int maxTareas;
  final int maxVersiones;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final perfil = Profile(
      id: aporte.userId,
      nombre: aporte.nombre,
      avatarUrl: aporte.avatarUrl,
      createdAt: DateTime.now(),
    );
    final ultima = aporte.ultimaActividad;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            UserAvatar(profile: perfil, radius: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(esYo ? '${aporte.nombre} (vos)' : aporte.nombre, style: theme.textTheme.titleMedium),
                Text(
                  [
                    if (aporte.rol == GroupRole.admin) 'Admin',
                    ultima == null ? 'Sin actividad todavía' : 'Activo ${formatearFecha(ultima, DateTime.now())}',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          _Barra(
            icono: Icons.task_alt,
            texto: '${aporte.tareasCompletadas} ${aporte.tareasCompletadas == 1 ? 'tarea completada' : 'tareas completadas'}'
                '${aporte.tareasPendientes > 0 ? ' · ${aporte.tareasPendientes} pendientes' : ''}',
            valor: aporte.tareasCompletadas,
            maximo: maxTareas,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 10),
          _Barra(
            icono: Icons.upload_file_rounded,
            texto: '${aporte.versionesSubidas} ${aporte.versionesSubidas == 1 ? 'versión subida' : 'versiones subidas'}',
            valor: aporte.versionesSubidas,
            maximo: maxVersiones,
            color: theme.colorScheme.tertiary,
          ),
        ]),
      ),
    );
  }
}

class _Barra extends StatelessWidget {
  const _Barra({
    required this.icono,
    required this.texto,
    required this.valor,
    required this.maximo,
    required this.color,
  });

  final IconData icono;
  final String texto;
  final int valor;
  final int maximo;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icono, size: 16, color: color),
        const SizedBox(width: 6),
        Text(texto, style: Theme.of(context).textTheme.bodyMedium),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: maximo == 0 ? 0 : valor / maximo,
          minHeight: 8,
          color: color,
          backgroundColor: color.withValues(alpha: 0.15),
        ),
      ),
    ]);
  }
}
