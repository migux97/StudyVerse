import 'dart:async';
import 'dart:typed_data';

import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/file_item.dart';
import '../domain/files_repository.dart';
import '../../../core/realtime/canales.dart';

const _bucket = 'archivos';

/// Versión con quién la subió y quién la guardó (hay dos referencias a profiles).
const _selectVersion = '*, uploader:profiles!file_versions_uploaded_by_fkey(nombre), '
    'guardador:profiles!file_versions_guardada_por_fkey(nombre)';

/// Archivo con su versión actual (y su autor) y quién lo tiene bloqueado.
const _selectArchivo = '*, '
    'current:file_versions!files_current_version_id_fkey($_selectVersion), '
    'locker:profiles!files_locked_by_fkey(nombre), '
    'pedidos:lock_requests(requested_by, created_at, '
    'requester:profiles!lock_requests_requested_by_fkey(nombre))';

/// Igual que [_selectArchivo], con quién lo mandó a la papelera y el grupo.
const _selectArchivoCompleto = '$_selectArchivo, '
    'eliminador:profiles!files_deleted_by_fkey(nombre), grupo:groups(nombre)';

class SupabaseFilesRepository implements FilesRepository {
  SupabaseFilesRepository(this._client);
  final SupabaseClient _client;

  StorageFileApi get _storage => _client.storage.from(_bucket);

  @override
  Future<List<Folder>> folders(String groupId) => _guard(() async {
        final rows = await _client.from('folders').select().eq('group_id', groupId);
        return rows.map(Folder.fromMap).toList();
      });

  @override
  Future<List<FileItem>> files(String groupId, String? folderId) => _guard(() async {
        var query = _client.from('files').select(_selectArchivo).eq('group_id', groupId).isFilter('deleted_at', null);
        query = folderId == null ? query.isFilter('folder_id', null) : query.eq('folder_id', folderId);
        final rows = await query;
        return rows.map(FileItem.fromMap).where((f) => f.current != null).toList()
          ..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
      });

  @override
  Future<List<FileVersion>> versions(String fileId) => _guard(() async {
        final rows = await _client
            .from('file_versions')
            .select(_selectVersion)
            .eq('file_id', fileId)
            .order('version_number', ascending: false);
        return rows.map(FileVersion.fromMap).toList();
      });

  @override
  Future<FileItem> file(String fileId) => _guard(() async {
        final row = await _client.from('files').select(_selectArchivoCompleto).eq('id', fileId).maybeSingle();
        if (row == null) throw const FilesFailure('Ese archivo ya no existe o no tenés acceso');
        return FileItem.fromMap(row);
      });

  @override
  Future<Uint8List> bytes(FileVersion version) => _guard(() => _storage.download(version.storagePath));

  @override
  Future<Folder> createFolder(String groupId, String? parentId, String nombre) => _guard(() async {
        final row = await _client
            .from('folders')
            .insert({
              'group_id': groupId,
              'parent_id': parentId,
              'nombre': nombre.trim(),
              'created_by': _client.auth.currentUser!.id,
            })
            .select()
            .single();
        return Folder.fromMap(row);
      });

  @override
  Future<void> renameFolder(String folderId, String nombre) => _guard(
      () => _client.from('folders').update({'nombre': nombre.trim()}).eq('id', folderId));

  @override
  Future<void> deleteFolder(String folderId) =>
      _guard(() => _client.rpc('delete_folder', params: {'p_folder_id': folderId}));

  @override
  Future<FileVersion> upload({
    required String groupId,
    required String? folderId,
    required String nombre,
    required Uint8List bytes,
    String? fileId,
    String? nota,
  }) =>
      _guard(() async {
        if (bytes.length > maxBytesPorArchivo) {
          throw FilesFailure('"$nombre" pesa más de ${maxBytesPorArchivo ~/ 1024 ~/ 1024} MB');
        }

        final plan = await _client.rpc('begin_upload', params: {
          'p_group_id': groupId,
          'p_folder_id': folderId,
          'p_nombre': nombre,
          'p_size_bytes': bytes.length,
          'p_file_id': fileId,
        }).single();

        await _storage.uploadBinary(
          plan['storage_path'] as String,
          bytes,
          fileOptions: FileOptions(
            contentType: lookupMimeType(nombre, headerBytes: bytes.take(32).toList()) ??
                'application/octet-stream',
          ),
        );

        final row = await _client.rpc('finish_upload', params: {
          'p_group_id': groupId,
          'p_folder_id': folderId,
          'p_nombre': nombre,
          'p_file_id': plan['file_id'],
          'p_version_number': plan['version_number'],
          'p_nota': nota,
        }).single();
        return FileVersion.fromMap(row);
      });

  @override
  Future<String> downloadUrl(FileVersion version, String nombre, {bool descargar = true, int segundos = 60}) =>
      _guard(() => _storage.createSignedUrl(
            version.storagePath,
            segundos,
            download: descargar ? DownloadBehavior.named(nombre) : null,
          ));

  @override
  Future<void> lock(String fileId, int minutos) => _guard(
      () => _client.rpc('lock_file', params: {'p_file_id': fileId, 'p_minutos': minutos}));

  @override
  Future<void> requestUnlock(String fileId) =>
      _guard(() => _client.rpc('request_unlock', params: {'p_file_id': fileId}));

  @override
  Stream<PedidoEntrante> pedidosEntrantes(String miId) =>
      escucharCanal(_client, Canales.pedidos(miId), evento: 'pedido').asyncExpand(_buscarPedido);

  // El aviso trae solo el id del pedido; se buscan el archivo y quién lo pide.
  Stream<PedidoEntrante> _buscarPedido(Map<String, dynamic> aviso) async* {
    try {
      final fila = await _client
          .from('lock_requests')
          .select('file_id, group_id, file:files(nombre, folder_id), '
              'requester:profiles!lock_requests_requested_by_fkey(nombre)')
          .eq('id', aviso['pedido'] as String)
          .maybeSingle();
      if (fila == null) return;
      final archivo = fila['file'] as Map<String, dynamic>;
      yield PedidoEntrante(
        fileId: fila['file_id'] as String,
        groupId: fila['group_id'] as String,
        folderId: archivo['folder_id'] as String?,
        archivo: archivo['nombre'] as String,
        quien: (fila['requester'] as Map<String, dynamic>?)?['nombre'] as String? ?? 'Alguien',
      );
    } on PostgrestException {
      // Si ya no existe (lo liberaron al toque), no hay nada que avisar.
    }
  }

  @override
  Future<void> unlock(String fileId) =>
      _guard(() => _client.rpc('unlock_file', params: {'p_file_id': fileId}));

  @override
  Future<FileVersion> restore(String versionId) => _guard(() async {
        final row =
            await _client.rpc('restore_version', params: {'p_version_id': versionId}).single();
        return FileVersion.fromMap(row);
      });

  @override
  Future<void> guardarVersion(String versionId, String? nombre) => _guard(
      () => _client.rpc('guardar_version', params: {'p_version_id': versionId, 'p_nombre': nombre}));

  @override
  Future<void> rename(String fileId, String nombre) => _guard(
      () => _client.rpc('rename_file', params: {'p_file_id': fileId, 'p_nombre': nombre}));

  @override
  Future<void> delete(String fileId) => _guard(() => _client.rpc('delete_file', params: {'p_file_id': fileId}));

  @override
  Future<List<FileItem>> papelera(String groupId) => _guard(() async {
        final rows = await _client
            .from('files')
            .select(_selectArchivoCompleto)
            .eq('group_id', groupId)
            .not('deleted_at', 'is', null)
            .order('deleted_at', ascending: false);
        return rows.map(FileItem.fromMap).toList();
      });

  @override
  Future<void> restaurar(String fileId) =>
      _guard(() => _client.rpc('restaurar_archivo', params: {'p_file_id': fileId}));

  @override
  Future<void> eliminarDefinitivo(String fileId) =>
      _guard(() => _client.rpc('eliminar_definitivo', params: {'p_file_id': fileId}));

  @override
  Future<List<FileItem>> destacados() => _guard(() async {
        final rows = await _client
            .from('destacados')
            .select('created_at, file:files($_selectArchivoCompleto)')
            .order('created_at', ascending: false);
        return _deFilas(rows);
      });

  @override
  Future<List<FileItem>> recientes() => _guard(() async {
        final rows = await _client
            .from('vistos')
            .select('visto_at, file:files($_selectArchivoCompleto)')
            .order('visto_at', ascending: false)
            .limit(12);
        return _deFilas(rows);
      });

  /// Filas con un archivo embebido: se descartan los de la papelera y los que
  /// ya no se ven (por ejemplo, de un grupo del que salí).
  List<FileItem> _deFilas(List<Map<String, dynamic>> rows) => [
        for (final r in rows)
          if (r['file'] case final Map<String, dynamic> f)
            if (FileItem.fromMap(f) case final a when !a.enPapelera && a.current != null) a,
      ];

  @override
  Future<void> destacar(String fileId, {required bool destacado}) => _guard(() async {
        if (destacado) {
          await _client.from('destacados').upsert(
            {'user_id': _client.auth.currentUser!.id, 'file_id': fileId},
            ignoreDuplicates: true,
          );
        } else {
          await _client.from('destacados').delete().eq('file_id', fileId);
        }
      });

  @override
  Future<void> marcarVisto(String fileId) =>
      _guard(() => _client.rpc('marcar_visto', params: {'p_file_id': fileId}));

  @override
  Future<List<ResultadoBusqueda>> buscar(String texto) => _guard(() async {
        final rows = await _client.rpc('buscar_archivos', params: {'p_texto': texto}) as List;
        return rows.map((r) => ResultadoBusqueda.fromMap(r as Map<String, dynamic>)).toList();
      });

  @override
  Stream<void> changes(String groupId) => escucharCanal(_client, Canales.archivos(groupId));

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on PostgrestException catch (e) {
      throw FilesFailure(traducirErrorArchivos(e.code, e.message));
    } on StorageException catch (e) {
      throw FilesFailure(traducirErrorStorage(e.statusCode, e.message));
    }
  }
}

/// Las funciones SQL ya devuelven mensajes en español; el resto se traduce acá.
String traducirErrorArchivos(String? code, String message) {
  switch (code) {
    case 'P0001':
    case 'P0002':
      return message;
    case '42501':
      // Los de las funciones vienen en español; los de RLS, no.
      return message.startsWith('new row') || message.startsWith('permission denied')
          ? 'No tenés permiso para hacer esto'
          : message;
    case '23505':
      return 'Ya hay una carpeta con ese nombre acá';
    case '23514':
      return 'El nombre no es válido';
  }
  return 'Algo salió mal. Probá de nuevo';
}

String traducirErrorStorage(String? statusCode, String message) {
  switch (statusCode) {
    case '413':
      return 'El archivo supera el tamaño máximo permitido';
    case '403':
      return 'No tenés permiso para subir archivos a este grupo';
    case '409':
      return 'Ese archivo ya se estaba subiendo. Probá de nuevo';
  }
  return 'Se cortó la conexión. Probá de nuevo';
}
