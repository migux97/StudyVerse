import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyverse/features/calendario/domain/calendario.dart';
import 'package:studyverse/features/files/domain/file_item.dart';
import 'package:studyverse/features/files/presentation/explorer_list.dart';
import 'package:studyverse/features/groups/domain/group.dart';

void main() {
  test('Folder lee si es materia y su color', () {
    final c = Folder.fromMap({
      'id': 'c',
      'group_id': 'g',
      'parent_id': null,
      'nombre': 'Química',
      'created_at': '2026-11-01T12:00:00Z',
      'es_materia': true,
      'color': 3,
    });
    expect(c.esMateria, isTrue);
    expect(c.color, 3);
    expect(Folder.fromMap({'id': 'd', 'group_id': 'g', 'nombre': 'x', 'created_at': '2026-11-01T12:00:00Z'}).esMateria,
        isFalse);
  });

  test('Group trae sus materias ordenadas', () {
    final g = Group.fromMap({
      'id': 'g1',
      'nombre': 'Segundo año',
      'invite_code': 'ABCD2345',
      'created_at': '2026-11-01T12:00:00Z',
      'materias': [
        {'nombre': 'Química', 'es_materia': true},
        {'nombre': 'análisis II', 'es_materia': true},
      ],
    });
    expect(g.materias, ['análisis II', 'Química']);
  });

  test('la materia de una tarea: su carpeta, o la de arriba', () {
    expect(materiaDe({'nombre': 'Química', 'es_materia': true, 'color': 2}), (nombre: 'Química', color: 2));
    expect(
      materiaDe({
        'nombre': 'TP 1',
        'es_materia': false,
        'padre': {'nombre': 'Física II', 'es_materia': true, 'color': 0},
      }),
      (nombre: 'Física II', color: 0),
    );
    expect(materiaDe({'nombre': 'Anexos', 'es_materia': false, 'padre': null}), isNull);
    expect(materiaDe(null), isNull);
  });

  testWidgets('el explorador muestra las materias primero', (tester) async {
    final carpetas = [
      Folder(id: 'a', groupId: 'g', nombre: 'Apuntes', createdAt: DateTime(2026)),
      Folder(id: 'q', groupId: 'g', nombre: 'Química', createdAt: DateTime(2026), esMateria: true, color: 1),
    ];
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: ExplorerList(carpetas: carpetas, archivos: const [], miId: 'ana', soyAdmin: true, onAbrirCarpeta: (_) {}),
        ),
      ),
    ));
    final quimica = tester.getTopLeft(find.text('Química')).dy;
    final apuntes = tester.getTopLeft(find.text('Apuntes')).dy;
    expect(quimica, lessThan(apuntes));
    expect(find.text('Materia'), findsOneWidget);
    expect(find.byIcon(Icons.folder_special_rounded), findsOneWidget);
  });
}
