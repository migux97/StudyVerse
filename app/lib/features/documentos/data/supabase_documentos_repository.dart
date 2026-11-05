import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/realtime/canales.dart';
import '../domain/documento.dart';

class SupabaseDocumentosRepository implements DocumentosRepository {
  SupabaseDocumentosRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<ContenidoDocumento?> borrador(String fileId) => _guard(() async {
        final row = await _client
            .from('documentos')
            .select('contenido, updated_at, updated_by, base_version, autor:profiles!documentos_updated_by_fkey(nombre)')
            .eq('file_id', fileId)
            .maybeSingle();
        if (row == null) return null;
        return ContenidoDocumento(
          ops: row['contenido'] as List,
          borradorDe: (row['autor'] as Map<String, dynamic>?)?['nombre'] as String? ?? 'Alguien',
          autorId: row['updated_by'] as String?,
          baseVersion: row['base_version'] as int?,
          actualizado: DateTime.parse(row['updated_at'] as String),
        );
      });

  @override
  Future<DateTime> guardar(String fileId, List<dynamic> ops) => _guard(() async {
        final cuando = await _client.rpc('guardar_documento', params: {'p_file_id': fileId, 'p_contenido': ops});
        return DateTime.parse(cuando as String);
      });

  @override
  Stream<String> cambios(String groupId) => escucharCanal(_client, Canales.documentos(groupId))
      .map((m) => m['documento'] as String? ?? '')
      .where((id) => id.isNotEmpty);

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on PostgrestException catch (e) {
      throw DocumentoFailure(e.code == 'P0001' || e.code == 'P0002' ? e.message : 'No se pudo guardar el documento');
    } on DocumentoFailure {
      rethrow;
    } on Exception {
      throw const DocumentoFailure('Sin conexión. Lo guardamos cuando vuelva', sinConexion: true);
    }
  }
}
