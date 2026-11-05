import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:studyverse/features/files/domain/file_item.dart';
import 'package:studyverse/features/files/domain/files_repository.dart';
import 'package:studyverse/features/files/presentation/files_providers.dart';
import 'package:studyverse/features/files/presentation/uploads_controller.dart';

class _MockFilesRepository extends Mock implements FilesRepository {}

void main() {
  late _MockFilesRepository repo;
  late ProviderContainer container;

  setUpAll(() => registerFallbackValue(Uint8List(0)));

  setUp(() {
    repo = _MockFilesRepository();
    container = ProviderContainer(overrides: [filesRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
  });

  Subida subida(String nombre) => Subida(nombre: nombre, tamano: 3, leer: () async => Uint8List(3));

  Future<void> subir(List<Subida> s) => container
      .read(uploadsProvider.notifier)
      .subir(groupId: 'g', folderId: null, subidas: s);

  testWidgets('"Archivo subido" se va solo a los pocos segundos', (tester) async {
    when(() => repo.upload(
          groupId: any(named: 'groupId'),
          folderId: any(named: 'folderId'),
          nombre: any(named: 'nombre'),
          bytes: any(named: 'bytes'),
          fileId: any(named: 'fileId'),
          nota: any(named: 'nota'),
        )).thenAnswer((_) async => FileVersion(
          id: 'v', fileId: 'f', versionNumber: 1, storagePath: 'p', sizeBytes: 3, createdAt: DateTime(2026)));
    container.listen(uploadsProvider, (_, _) {});

    await subir([subida('a.txt')]);
    expect(container.read(uploadsProvider).single.estado, EstadoSubida.lista);

    await tester.pump(UploadsController.ocultarDespues - const Duration(seconds: 1));
    expect(container.read(uploadsProvider), isNotEmpty);
    await tester.pump(const Duration(seconds: 2));
    expect(container.read(uploadsProvider), isEmpty);
  });

  testWidgets('si alguno falló, el aviso queda hasta cerrarlo', (tester) async {
    when(() => repo.upload(
          groupId: any(named: 'groupId'),
          folderId: any(named: 'folderId'),
          nombre: any(named: 'nombre'),
          bytes: any(named: 'bytes'),
          fileId: any(named: 'fileId'),
          nota: any(named: 'nota'),
        )).thenThrow(const FilesFailure('El grupo no tiene más espacio'));
    container.listen(uploadsProvider, (_, _) {});

    await subir([subida('b.txt')]);
    await tester.pump(const Duration(seconds: 30));
    expect(container.read(uploadsProvider).single.error, 'El grupo no tiene más espacio');

    container.read(uploadsProvider.notifier).limpiar();
    expect(container.read(uploadsProvider), isEmpty);
  });
}
