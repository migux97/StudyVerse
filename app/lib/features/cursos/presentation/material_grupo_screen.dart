import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../groups/presentation/group_shell.dart' show Aviso, GroupLoader;
import 'curso_paneles.dart';

/// El material que subió el docente, visto desde un grupo del curso.
class MaterialGrupoScreen extends StatelessWidget {
  const MaterialGrupoScreen({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context) => GroupLoader(
        groupId: groupId,
        builder: (g) => Scaffold(
          appBar: AppBar(
            leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.grupo(groupId))),
            title: const Text('Material del docente'),
          ),
          body: g.cursoId == null
              ? const Aviso(icono: Icons.school_outlined, texto: 'El grupo no está en un curso')
              : ListaMaterial(cursoId: g.cursoId!, esDocente: false),
        ),
      );
}
