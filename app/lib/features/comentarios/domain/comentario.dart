import '../../../core/errors.dart';
import '../../auth/domain/profile.dart';

class ComentarioFailure extends AppFailure {
  const ComentarioFailure(super.mensaje);
}

class Comentario {
  const Comentario({
    required this.id,
    required this.fileId,
    required this.groupId,
    this.autor,
    required this.texto,
    this.menciones = const [],
    required this.createdAt,
    this.archivo,
  });

  final String id;
  final String fileId;
  final String groupId;

  /// Perfil de quien lo escribió (null si ya no existe la cuenta).
  final Profile? autor;
  final String texto;
  final List<String> menciones;
  final DateTime createdAt;

  /// Nombre del archivo (solo en los avisos de mención).
  final String? archivo;

  factory Comentario.fromMap(Map<String, dynamic> m) => Comentario(
        id: m['id'] as String,
        fileId: m['file_id'] as String,
        groupId: m['group_id'] as String,
        autor: m['autor_perfil'] == null ? null : Profile.fromMap(m['autor_perfil'] as Map<String, dynamic>),
        texto: m['texto'] as String,
        menciones: [for (final u in (m['menciones'] as List? ?? const [])) u as String],
        createdAt: DateTime.parse(m['created_at'] as String),
        archivo: (m['archivo'] as Map<String, dynamic>?)?['nombre'] as String?,
      );
}

/// Partes del texto: lo normal y las menciones (@usuario), para resaltarlas.
List<({String texto, bool mencion})> partesDelTexto(String texto) {
  final partes = <({String texto, bool mencion})>[];
  var desde = 0;
  for (final m in RegExp(r'@[a-zA-Z0-9][a-zA-Z0-9._]{1,18}[a-zA-Z0-9]').allMatches(texto)) {
    if (m.start > desde) partes.add((texto: texto.substring(desde, m.start), mencion: false));
    partes.add((texto: m.group(0)!, mencion: true));
    desde = m.end;
  }
  if (desde < texto.length) partes.add((texto: texto.substring(desde), mencion: false));
  return partes;
}

/// Si el cursor está escribiendo una mención ("hola @an|"), devuelve lo
/// escrito después de la @ ("an") y dónde empieza. Si no, null.
({String buscado, int inicio})? mencionEnCurso(String texto, int cursor) {
  if (cursor < 0 || cursor > texto.length) return null;
  final antes = texto.substring(0, cursor);
  final m = RegExp(r'(^|\s)@([a-zA-Z0-9._]{0,20})$').firstMatch(antes);
  if (m == null) return null;
  return (buscado: m.group(2)!.toLowerCase(), inicio: cursor - m.group(2)!.length - 1);
}

/// Reemplaza la mención en curso por "@usuario " y devuelve el texto y dónde
/// queda el cursor.
({String texto, int cursor}) completarMencion(String texto, int inicio, int cursor, String usuario) {
  final nuevo = '${texto.substring(0, inicio)}@$usuario ${texto.substring(cursor)}';
  return (texto: nuevo, cursor: inicio + usuario.length + 2);
}

abstract interface class ComentariosRepository {
  Future<List<Comentario>> comentarios(String fileId);
  Future<void> comentar({required String fileId, required String groupId, required String texto});
  Future<void> borrar(String id);

  /// Emite el id del archivo cada vez que cambian sus comentarios.
  Stream<String> cambios(String groupId);

  /// Comentarios en los que me mencionan, en vivo.
  Stream<Comentario> menciones(String miId);
}
