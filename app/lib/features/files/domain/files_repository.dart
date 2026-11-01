import 'dart:typed_data';

import '../../../core/errors.dart';
import 'file_item.dart';

class FilesFailure extends AppFailure {
  const FilesFailure(super.mensaje);
}

/// Límite por archivo del bucket de Storage.
const maxBytesPorArchivo = 50 * 1024 * 1024;

abstract interface class FilesRepository {
  Future<List<Folder>> folders(String groupId);
  Future<List<FileItem>> files(String groupId, String? folderId);
  Future<List<FileVersion>> versions(String fileId);

  Future<Folder> createFolder(String groupId, String? parentId, String nombre);
  Future<void> renameFolder(String folderId, String nombre);
  Future<void> deleteFolder(String folderId);

  /// Sube un archivo. Si ya hay uno con ese nombre en la carpeta (o se pasa
  /// [fileId]), queda como versión nueva.
  Future<FileVersion> upload({
    required String groupId,
    required String? folderId,
    required String nombre,
    required Uint8List bytes,
    String? fileId,
    String? nota,
  });

  /// URL firmada (corta) para abrir una versión, o descargarla con su nombre
  /// real si [descargar] (en Storage se llama `v{n}`).
  Future<String> downloadUrl(FileVersion version, String nombre, {bool descargar = true});

  /// "Estoy editando este archivo". Si ya era mío, renueva las 24 h.
  Future<void> lock(String fileId);

  /// Desbloquea (propio, vencido, o cualquiera si sos admin).
  Future<void> unlock(String fileId);

  Future<FileVersion> restore(String versionId);
  Future<void> rename(String fileId, String nombre);
  Future<void> delete(String fileId);

  /// Emite cada vez que cambian carpetas, archivos o versiones del grupo.
  Stream<void> changes(String groupId);
}
