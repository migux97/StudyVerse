import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/forms/validar.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/auth_layout.dart';
import '../../../core/widgets/text_input_dialog.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/presentation/user_avatar.dart';
import '../../groups/presentation/groups_providers.dart';
import '../domain/curso.dart';
import 'cursos_providers.dart';
import '../../groups/presentation/group_shell.dart' show Aviso;

/// Inicio de una cuenta de docente: sus cursos y, si también es integrante de
/// algún grupo, esos grupos.
class InicioDocente extends ConsumerWidget {
  const InicioDocente({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(currentProfileProvider).value;
    final cursos = ref.watch(misCursosProvider);
    final grupos = ref.watch(myGroupsProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis cursos'),
        actions: [
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
      floatingActionButton: (cursos.value?.isNotEmpty ?? false)
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Nuevo curso'),
              onPressed: () => crearCurso(context, ref),
            )
          : null,
      body: cursos.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Aviso(
          icono: Icons.cloud_off_outlined,
          texto: e is CursosFailure ? e.mensaje : 'Algo salió mal. Probá de nuevo',
          accion: FilledButton(onPressed: () => ref.invalidate(misCursosProvider), child: const Text('Reintentar')),
        ),
        data: (lista) => lista.isEmpty && grupos.isEmpty
            ? _SinCursos(nombre: perfil?.nombre, onCrear: () => crearCurso(context, ref))
            : RefreshIndicator(
                onRefresh: () => ref.refresh(misCursosProvider.future),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          if (lista.isEmpty)
                            Card(
                              child: ListTile(
                                leading: const Icon(Icons.school_outlined),
                                title: const Text('Creá tu primer curso'),
                                subtitle: const Text('Los grupos de tu clase se suman con su código'),
                                trailing: FilledButton(
                                    onPressed: () => crearCurso(context, ref), child: const Text('Crear')),
                              ),
                            ),
                          for (final c in lista) _CursoCard(curso: c),
                          if (grupos.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
                              child: Text('Grupos en los que participás', style: Theme.of(context).textTheme.titleSmall),
                            ),
                            for (final g in grupos)
                              Card(
                                child: ListTile(
                                  leading: Icon(Icons.folder_rounded, color: Theme.of(context).colorScheme.primary),
                                  title: Text(g.nombre),
                                  onTap: () => context.push(Routes.grupo(g.id)),
                                ),
                              ),
                          ],
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _CursoCard extends StatelessWidget {
  const _CursoCard({required this.curso});
  final Curso curso;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = curso.cantidadGrupos;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Icon(Icons.school_outlined, color: scheme.onPrimaryContainer),
        ),
        title: Text(curso.nombre, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(n == 0 ? 'Todavía no se sumó ningún grupo' : (n == 1 ? '1 grupo' : '$n grupos')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(Routes.curso(curso.id)),
      ),
    );
  }
}

class _SinCursos extends StatelessWidget {
  const _SinCursos({required this.nombre, required this.onCrear});
  final String? nombre;
  final VoidCallback onCrear;

  @override
  Widget build(BuildContext context) {
    final primer = nombre?.split(' ').first;
    return Aviso(
      icono: Icons.school_outlined,
      texto: primer == null ? 'Te damos la bienvenida' : 'Hola, $primer',
      detalle: '1. Creá un curso por cada comisión que tengas.\n'
          '2. Pasale el código a tu clase.\n'
          '3. El admin de cada grupo lo suma al curso, y vas a ver sus archivos, tareas y aportes.',
      accion: FilledButton.icon(icon: const Icon(Icons.add), label: const Text('Crear un curso'), onPressed: onCrear),
    );
  }
}

Future<void> crearCurso(BuildContext context, WidgetRef ref) async {
  final nombre = await pedirTexto(
    context,
    titulo: 'Nuevo curso',
    etiqueta: 'Nombre del curso',
    ejemplo: 'Ej.: Física II · Comisión 3',
    accion: 'Crear',
    maximo: 120,
    validator: Validar.texto(vacio: 'Ingresá el nombre del curso', max: 120),
  );
  if (nombre == null || !context.mounted) return;
  try {
    final c = await ref.read(cursosRepositoryProvider).crear(nombre);
    ref.invalidate(misCursosProvider);
    if (context.mounted) context.push(Routes.curso(c.id));
  } on CursosFailure catch (e) {
    if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
  }
}

/// Copia el código del curso.
Future<void> copiarCodigo(BuildContext context, Curso c) async {
  await Clipboard.setData(ClipboardData(text: c.codigoVisible));
  if (context.mounted) mostrarMensaje(context, 'Código copiado');
}
