import 'dart:async';
import 'dart:typed_data';

import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/file_item.dart';
import '../domain/files_repository.dart';
import '../../../core/realtime/canales.dart';

const _bucket = 'archivos';

/// Archivo con su versión actual (y su autor) y quién lo tiene bloqueado.
const _selectArchivo = '*, '
    'current:file_versions!files_current_version_id_fkey(*, uploader:profiles(nombre)), '
    'locker:profiles!files_locked_by_fkey(nombre), '
    'pedidos:lock_requests(requested_by, created_at, '
    'requester:profiles!lock_requests_requested_by_fkey(nombre))';

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
        var query = _client.from('files').select(_selectArchivo).eq('group_id', groupId);
        query = folderId == null ? query.isFilter('folder_id', null) : query.eq('folder_id', folderId);
        final rows = await query;
        return rows.map(FileItem.fromMap).where((f) => f.current != null).toList()
          ..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
      });

  @override
  Future<List<FileVersion>> versions(String fileId) => _guard(() async {
        final rows = await _client
            .from('file_versions')
            .select('*, uploader:profiles(nombre)')
            .eq('file_id', fileId)
            .order('version_number', ascending: false);
        return rows.map(FileVersion.fromMap).toList();
      });

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
  Future<String> downloadUrl(FileVersion version, String nombre, {bool descargar = true}) =>
      _guard(() => _storage.createSignedUrl(
            version.storagePath,
            60,
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
  Future<void> rename(String fileId, String nombre) => _guard(
      () => _client.rpc('rename_file', params: {'p_file_id': fileId, 'p_nombre': nombre}));

  @override
  Future<void> delete(String fileId) => _guard(() async {
        final rutas = await _client.rpc('delete_file', params: {'p_file_id': fileId}) as List;
        // La base ya no lo tiene; si falla el borrado en Storage quedan objetos
        // huérfanos, pero el archivo desaparece igual para el grupo.
        if (rutas.isNotEmpty) {
          try {
            await _storage.remove(rutas.cast<String>());
          } on StorageException {
            // Se ignora a propósito (ver arriba).
          }
        }
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
