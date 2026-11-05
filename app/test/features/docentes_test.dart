import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyverse/features/auth/domain/profile.dart';
import 'package:studyverse/features/cursos/domain/curso.dart';
import 'package:studyverse/features/files/domain/file_item.dart';
import 'package:studyverse/features/files/presentation/explorer_list.dart';
import 'package:studyverse/features/groups/domain/group.dart';

void main() {
  test('el perfil lee si es docente', () {
    final base = {'id': 'u', 'nombre': 'Profe', 'created_at': '2026-11-01T12:00:00Z'};
    expect(Profile.fromMap({...base, 'tipo_cuenta': 'docente'}).esDocente, isTrue);
    expect(Profile.fromMap(base).tipo, TipoCuenta.estudiante);
    expect(const CambiosPerfil(tipo: TipoCuenta.docente).toMap(), {'tipo_cuenta': 'docente'});
  });

  test('curso: código legible y cantidad de grupos', () {
    final c = Curso.fromMap({
      'id': 'c',
      'nombre': 'Física II · Comisión 3',
      'codigo': 'ABCDE23456',
      'docente_id': 'p',
      'docente': {'nombre': 'Profe'},
      'created_at': '2026-11-01T12:00:00Z',
      'cantidad_grupos': 4,
    });
    expect(c.codigoVisible, 'ABCDE-23456');
    expect(c.cantidadGrupos, 4);
    expect(c.docenteNombre, 'Profe');
  });

  test('grupo del curso: integrantes, avance y entregas', () {
    final g = GrupoDelCurso.fromMap({
      'id': 'g',
      'nombre': 'Grupo 4',
      'integrantes': ['Ana', 'Juan'],
      'tareas': ['hecha', 'entregada', 'pendiente'],
      'materias': ['Física II'],
    });
    expect(g.integrantes, ['Ana', 'Juan']);
    expect((g.tareasHechas, g.tareasTotal, g.entregadas), (1, 3, 1));
    expect(g.materias, ['Física II']);
  });

  test('un grupo sin rol propio se ve en solo lectura, con su curso', () {
    final g = Group.fromMap({
      'id': 'g',
      'nombre': 'Grupo 4',
      'invite_code': 'ABCD2345',
      'created_at': '2026-11-01T12:00:00Z',
      'curso_id': 'c',
      'curso': {
        'nombre': 'Física II',
        'docente': {'nombre': 'Profe'},
      },
    });
    expect(g.soloLectura, isTrue);
    expect((g.cursoNombre, g.cursoDocente), ('Física II', 'Profe'));
    expect(Group.fromMap({'id': 'g', 'nombre': 'x', 'invite_code': 'A', 'created_at': '2026-11-01T12:00:00Z'},
            miRol: GroupRole.miembro)
        .soloLectura, isFalse);
  });

  testWidgets('en solo lectura, el menú de un archivo solo deja abrir, descargar y ver el historial', (tester) async {
    final ahora = DateTime.now();
    final archivo = FileItem(
      id: 'f',
      groupId: 'g',
      nombre: 'Informe.docx',
      current: FileVersion(id: 'v', fileId: 'f', versionNumber: 2, storagePath: 'x', sizeBytes: 10, createdAt: ahora),
      createdAt: ahora,
    );
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: ExplorerList(
            carpetas: [Folder(id: 'c', groupId: 'g', nombre: 'TP 1', createdAt: ahora)],
            archivos: [archivo],
            miId: 'profe',
            soyAdmin: false,
            soloLectura: true,
            onAbrirCarpeta: (_) {},
          ),
        ),
      ),
    ));
    expect(find.byTooltip('Opciones'), findsOneWidget, reason: 'las carpetas no tienen menú');
    await tester.tap(find.byTooltip('Opciones'));
    await tester.pumpAndSettle();
    expect(find.text('Abrir'), findsOneWidget);
    expect(find.text('Descargar'), findsOneWidget);
    expect(find.text('Historial (v2)'), findsOneWidget);
    expect(find.text('Subir nueva versión'), findsNothing);
    expect(find.text('Cambiar nombre'), findsNothing);
  });
}
