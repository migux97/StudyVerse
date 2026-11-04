import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyverse/features/files/domain/file_item.dart';
import 'package:studyverse/features/files/presentation/explorer_list.dart';

FileItem _archivo(String nombre, {int version = 1, String? lockedBy, String? lockedByNombre}) {
  final ahora = DateTime.now();
  return FileItem(
    id: nombre,
    groupId: 'g',
    nombre: nombre,
    current: FileVersion(
      id: 'v-$nombre',
      fileId: nombre,
      versionNumber: version,
      storagePath: 'x',
      sizeBytes: 2048,
      uploaderNombre: 'Ana',
      createdAt: ahora.subtract(const Duration(minutes: 5)),
    ),
    lockedBy: lockedBy,
    lockedByNombre: lockedByNombre,
    lockedAt: lockedBy == null ? null : ahora,
    lockUntil: lockedBy == null ? null : ahora.add(const Duration(hours: 2)),
    createdBy: 'ana',
    createdAt: ahora,
  );
}

Widget _app(Widget child, {double ancho = 500}) => ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: Center(child: SizedBox(width: ancho, height: 700, child: child))),
      ),
    );

void main() {
  final carpeta = Folder(id: 'c', groupId: 'g', nombre: 'Anexos', createdAt: DateTime(2026));

  testWidgets('muestra carpetas, archivos, versión y quién edita', (tester) async {
    await tester.pumpWidget(_app(ExplorerList(
      carpetas: [carpeta],
      archivos: [
        _archivo('Informe.docx', version: 3, lockedBy: 'juan', lockedByNombre: 'Juan'),
        _archivo('Consigna.pdf'),
      ],
      miId: 'ana',
      soyAdmin: false,
      onAbrirCarpeta: (_) {},
    )));

    expect(find.text('Anexos'), findsOneWidget);
    expect(find.text('Informe.docx'), findsOneWidget);
    expect(find.text('v3'), findsOneWidget);
    expect(find.text('v1'), findsNothing, reason: 'la v1 no lleva etiqueta');
    expect(find.text('🔒 Juan está editando'), findsOneWidget);
    expect(find.text('Ana · hace 5 min · 2 KB'), findsNWidgets(2));
  });

  testWidgets('si otro edita: pedirle o subir como copia, sin pisar el original', (tester) async {
    await tester.pumpWidget(_app(ExplorerList(
      carpetas: const [],
      archivos: [_archivo('Informe.docx', lockedBy: 'juan', lockedByNombre: 'Juan')],
      miId: 'ana',
      soyAdmin: false,
      onAbrirCarpeta: (_) {},
    )));

    await tester.tap(find.byTooltip('Opciones'));
    await tester.pumpAndSettle();

    expect(find.text('Pedirle a Juan que lo libere'), findsOneWidget);
    expect(find.text('Subir mis cambios como copia'), findsOneWidget);
    expect(find.text('Forzar desbloqueo'), findsNothing, reason: 'no soy admin');
    expect(find.text('Subir nueva versión'), findsNothing);
    final renombrar = tester.widget<ListTile>(find.widgetWithText(ListTile, 'Cambiar nombre'));
    expect(renombrar.enabled, isFalse);
  });

  testWidgets('con panel lateral, tocar un archivo lo elige', (tester) async {
    FileItem? elegido;
    await tester.pumpWidget(_app(ExplorerList(
      carpetas: const [],
      archivos: [_archivo('Informe.docx')],
      miId: 'ana',
      soyAdmin: true,
      onAbrirCarpeta: (_) {},
      onSeleccionar: (a) => elegido = a,
    )));

    await tester.tap(find.text('Informe.docx'));
    expect(elegido?.nombre, 'Informe.docx');
  });
}
