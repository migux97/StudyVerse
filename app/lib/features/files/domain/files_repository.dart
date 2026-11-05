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

  /// Un archivo con su versión actual (para el visor).
  Future<FileItem> file(String fileId);

  /// El contenido de una versión (para mostrar texto, documentos, planillas).
  Future<Uint8List> bytes(FileVersion version);

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
  /// [segundos]: lo que dura la URL (más para video y audio, que piden de a pedazos).
  Future<String> downloadUrl(FileVersion version, String nombre, {bool descargar = true, int segundos = 60});

  /// "Estoy editando este archivo" por [minutos] (15 a 1440). Si ya era mío, lo renueva.
  Future<void> lock(String fileId, int minutos);

  /// Le pide a quien lo está editando que lo libere.
  Future<void> requestUnlock(String fileId);

  /// Pedidos que me hacen a mí, en vivo (para avisarme en cualquier pantalla).
  Stream<PedidoEntrante> pedidosEntrantes(String miId);

  /// Desbloquea (propio, vencido, o cualquiera si sos admin).
  Future<void> unlock(String fileId);

  Future<FileVersion> restore(String versionId);

  /// Guarda la versión con [nombre] (o le cambia el nombre). Con `null` la
  /// quita de las guardadas (con el plan gratis puede dejar de verse).
  Future<void> guardarVersion(String versionId, String? nombre);
  Future<void> rename(String fileId, String nombre);
  /// Lo manda a la papelera (se puede restaurar durante [diasPapelera] días).
  Future<void> delete(String fileId);

  /// Lo que está en la papelera del grupo, lo último primero.
  Future<List<FileItem>> papelera(String groupId);
  Future<void> restaurar(String fileId);
  Future<void> eliminarDefinitivo(String fileId);

  /// Destacados y recientes de todos mis grupos.
  Future<List<FileItem>> destacados();
  Future<List<FileItem>> recientes();
  Future<void> destacar(String fileId, {required bool destacado});
  Future<void> marcarVisto(String fileId);

  /// Busca por nombre en todos mis grupos (sin importar tildes).
  Future<List<ResultadoBusqueda>> buscar(String texto);

  /// Emite cada vez que cambian carpetas, archivos o versiones del grupo.
  Stream<void> changes(String groupId);
}
