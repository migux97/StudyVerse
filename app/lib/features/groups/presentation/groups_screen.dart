import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/presentation/user_avatar.dart';
import '../domain/group.dart';
import 'group_dialogs.dart';
import 'groups_providers.dart';
import '../../inicio/presentation/inicio_secciones.dart';

/// Pantalla principal: los grupos del usuario, como carpetas.
class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(currentProfileProvider).value;
    final grupos = ref.watch(myGroupsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis grupos'),
        actions: [
          IconButton(
            tooltip: 'Calendario',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => context.push(Routes.calendario),
          ),
          IconButton(
            tooltip: 'Unirme con un código',
            icon: const Icon(Icons.group_add_outlined),
            onPressed: () => unirseConCodigo(context, ref),
          ),
          if (perfil != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton(
                tooltip: 'Mi perfil',
                icon: UserAvatar(profile: perfil),
                onPressed: () => context.push(Routes.perfil),
              ),
            ),
        ],
      ),
      floatingActionButton: (grupos.value?.isNotEmpty ?? false)
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Nuevo grupo'),
              onPressed: () => crearGrupo(context, ref),
            )
          : null,
      body: grupos.when(
        skipLoadingOnReload: true,
        loading:() => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Error(
          mensaje: e.toString(),
          onReintentar: () => ref.invalidate(myGroupsProvider),
        ),
        data: (lista) => lista.isEmpty
            ? _SinGrupos(nombre: perfil?.nombre)
            : RefreshIndicator(
                onRefresh: () => ref.refresh(myGroupsProvider.future),
                child: _ListaGrupos(grupos: lista),
              ),
      ),
    );
  }
}

class _ListaGrupos extends StatelessWidget {
  const _ListaGrupos({required this.grupos});
  final List<Group> grupos;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // Celular: lista. PC / tablet: grilla de carpetas. Arriba, como en Drive:
      // buscar, lo que se viene, destacados y recientes.
      final celular = constraints.maxWidth < 600;
      final lado = celular ? 16.0 : 24.0;
      return CustomScrollView(slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(lado, 8, lado, 0),
          sliver: SliverToBoxAdapter(
            child: Center(
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1200), child: const InicioSecciones())),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(lado + 4, 20, lado, 8),
          sliver: SliverToBoxAdapter(child: Text('Tus grupos', style: Theme.of(context).textTheme.titleSmall)),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(lado, 0, lado, 96),
          sliver: celular
              ? SliverList.separated(
                  itemCount: grupos.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _GrupoTile(grupo: grupos[i]),
                )
              : SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 280,
                    mainAxisExtent: 132,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: grupos.length,
                  itemBuilder: (_, i) => _GrupoCard(grupo: grupos[i]),
                ),
        ),
      ]);
    });
  }
}

String _detalle(Group g) {
  final n = g.cantidadMiembros;
  final integrantes = n == null ? null : (n == 1 ? '1 integrante' : '$n integrantes');
  final materias = switch (g.materias.length) {
    0 => null,
    1 || 2 => g.materias.join(', '),
    final n => '${g.materias.take(2).join(', ')} y ${n - 2} más',
  };
  return [materias, integrantes].whereType<String>().join(' · ');
}

class _GrupoTile extends StatelessWidget {
  const _GrupoTile({required this.grupo});
  final Group grupo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(Icons.folder_rounded, color: scheme.primary, size: 32),
        title: Text(grupo.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(_detalle(grupo), maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: grupo.soyAdmin ? const _AdminChip() : null,
        onTap: () => context.push(Routes.grupo(grupo.id)),
      ),
    );
  }
}

class _GrupoCard extends StatelessWidget {
  const _GrupoCard({required this.grupo});
  final Group grupo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(Routes.grupo(grupo.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.folder_rounded, color: theme.colorScheme.primary, size: 36),
                const Spacer(),
                if (grupo.soyAdmin) const _AdminChip(),
              ]),
              const Spacer(),
              Text(grupo.nombre,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(_detalle(grupo),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminChip extends StatelessWidget {
  const _AdminChip();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('Admin',
          style: TextStyle(fontSize: 12, color: scheme.onSecondaryContainer)),
    );
  }
}

class _SinGrupos extends ConsumerWidget {
  const _SinGrupos({this.nombre});
  final String? nombre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.folder_open_rounded, size: 64, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                nombre == null ? 'Hola' : 'Hola, ${nombre!.split(' ').first}',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Creá un grupo para tu TP o unite al de tus compañeros con el código que te pasaron.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Crear un grupo'),
                onPressed: () => crearGrupo(context, ref),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Unirme con un código'),
                onPressed: () => unirseConCodigo(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.mensaje, required this.onReintentar});
  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(mensaje, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onReintentar, child: const Text('Reintentar')),
        ]),
      );
}
