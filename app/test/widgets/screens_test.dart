import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tpdrive/features/auth/domain/auth_repository.dart';
import 'package:tpdrive/features/auth/domain/profile.dart';
import 'package:tpdrive/features/auth/presentation/auth_providers.dart';
import 'package:tpdrive/features/groups/domain/group.dart';
import 'package:tpdrive/features/groups/presentation/groups_providers.dart';
import 'package:tpdrive/features/groups/presentation/groups_screen.dart';
import 'package:tpdrive/features/tasks/domain/task.dart';
import 'package:tpdrive/features/tasks/presentation/tasks_providers.dart';
import 'package:tpdrive/features/tasks/presentation/tasks_screen.dart';

final _yo = Profile(id: 'ana', nombre: 'Ana López', createdAt: DateTime(2026));

final _grupo = Group(
  id: 'g',
  nombre: 'TP Final',
  inviteCode: 'ABCD2345',
  createdAt: DateTime(2026),
  miRol: GroupRole.admin,
  cantidadMiembros: 2,
);

/// Pantallas sin Supabase: los providers devuelven datos fijos.
List _overrides({List<Group> grupos = const [], List<Task> tareas = const []}) => [
      authStateProvider.overrideWith((ref) => Stream.value(const SessionUser(id: 'ana'))),
      currentProfileProvider.overrideWith(() => _PerfilFijo()),
      myGroupsProvider.overrideWith((ref) async => grupos),
      groupProvider.overrideWith((ref, id) async => _grupo),
      tasksProvider.overrideWith((ref, id) async => tareas),
    ];

class _PerfilFijo extends CurrentProfileNotifier {
  @override
  Future<Profile?> build() async => _yo;
}

Task _tarea(String titulo, {String? para, String? nombre, EstadoTarea estado = EstadoTarea.pendiente, int? enDias}) {
  final hoy = DateTime.now();
  return Task(
    id: titulo,
    groupId: 'g',
    titulo: titulo,
    assignedTo: para,
    assignedNombre: nombre,
    estado: estado,
    dueDate: enDias == null ? null : DateTime(hoy.year, hoy.month, hoy.day + enDias),
    createdAt: hoy,
  );
}

void main() {
  testWidgets('Mis grupos vacío: saluda y ofrece crear o unirse', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [..._overrides()],
      child: const MaterialApp(home: GroupsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Hola, Ana'), findsOneWidget);
    expect(find.text('Crear un grupo'), findsOneWidget);
    expect(find.text('Unirme con un código'), findsOneWidget);
  });

  testWidgets('Mis grupos: muestra cada grupo con materia e integrantes', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [..._overrides(grupos: [_grupo])],
      child: const MaterialApp(home: GroupsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('TP Final'), findsOneWidget);
    expect(find.text('2 integrantes'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
  });

  testWidgets('Tareas: secciones, "Vos", vencimientos y filtro Mías', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        ..._overrides(tareas: [
          _tarea('Introducción', para: 'ana', nombre: 'Ana López', enDias: 1),
          _tarea('Gráficos', para: 'juan', nombre: 'Juan', estado: EstadoTarea.enProgreso, enDias: -2),
          _tarea('Bibliografía', estado: EstadoTarea.hecha),
        ]),
      ],
      child: const MaterialApp(home: TasksScreen(groupId: 'g')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('En progreso · 1'), findsOneWidget);
    expect(find.text('Pendientes · 1'), findsOneWidget);
    expect(find.text('Hechas · 1'), findsOneWidget);
    expect(find.text('Bibliografía'), findsNothing, reason: 'las hechas arrancan plegadas');
    expect(find.text('Vos'), findsOneWidget);
    expect(find.text('Vence mañana'), findsOneWidget);
    expect(find.text('Venció hace 2 días'), findsOneWidget);

    await tester.tap(find.text('Mías'));
    await tester.pumpAndSettle();
    expect(find.text('Gráficos'), findsNothing);
    expect(find.text('Introducción'), findsOneWidget);
  });
}
