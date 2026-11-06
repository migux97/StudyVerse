import '../../../core/errors.dart';
import '../../auth/domain/profile.dart';

class ChatFailure extends AppFailure {
  const ChatFailure(super.mensaje);
}

/// Lo que se muestra del mensaje citado al responder.
class Cita {
  const Cita({required this.id, this.autorNombre, this.texto, required this.borrado});
  final String id;
  final String? autorNombre;
  final String? texto;
  final bool borrado;
}

class Mensaje {
  const Mensaje({
    required this.id,
    required this.groupId,
    this.autorId,
    this.autor,
    this.texto,
    this.fileId,
    this.archivoNombre,
    this.cita,
    required this.createdAt,
    this.editadoAt,
    this.borradoAt,
  });

  final String id;
  final String groupId;
  final String? autorId;
  final Profile? autor;
  final String? texto;
  final String? fileId;
  final String? archivoNombre;
  final Cita? cita;
  final DateTime createdAt;
  final DateTime? editadoAt;
  final DateTime? borradoAt;

  bool get borrado => borradoAt != null;
  bool get editado => editadoAt != null && !borrado;

  /// Fila de `mensajes` con el autor, el archivo y el mensaje citado embebidos.
  factory Mensaje.fromMap(Map<String, dynamic> m) {
    final r = m['respondido'] as Map<String, dynamic>?;
    final autor = m['autor_perfil'] as Map<String, dynamic>?;
    return Mensaje(
      id: m['id'] as String,
      groupId: m['group_id'] as String,
      autorId: m['autor'] as String?,
      autor: autor == null ? null : Profile.fromMap(autor),
      texto: m['texto'] as String?,
      fileId: m['file_id'] as String?,
      archivoNombre: (m['archivo'] as Map<String, dynamic>?)?['nombre'] as String?,
      cita: r == null
          ? null
          : Cita(
              id: r['id'] as String,
              autorNombre: (r['autor_perfil'] as Map<String, dynamic>?)?['nombre'] as String?,
              texto: r['texto'] as String?,
              borrado: r['borrado_at'] != null,
            ),
      createdAt: DateTime.parse(m['created_at'] as String),
      editadoAt: m['editado_at'] == null ? null : DateTime.parse(m['editado_at'] as String),
      borradoAt: m['borrado_at'] == null ? null : DateTime.parse(m['borrado_at'] as String),
    );
  }
}

/// Lo que va en la lista del chat: separadores de día, la marca de "nuevos"
/// y los mensajes (con si van pegados al anterior del mismo autor).
sealed class FilaChat {
  const FilaChat();
}

class FilaDia extends FilaChat {
  const FilaDia(this.dia);
  final DateTime dia;
}

class FilaNuevos extends FilaChat {
  const FilaNuevos();
}

class FilaMensaje extends FilaChat {
  const FilaMensaje(this.mensaje, {required this.seguido});
  final Mensaje mensaje;

  /// Mismo autor que el anterior y a menos de 5 minutos: sin nombre ni foto.
  final bool seguido;
}

/// Arma las filas a partir de los mensajes (del más viejo al más nuevo). La
/// marca de nuevos va antes del primer mensaje ajeno posterior a [leidoHasta].
List<FilaChat> armarFilas(List<Mensaje> mensajes, {DateTime? leidoHasta, String? miId}) {
  final filas = <FilaChat>[];
  DateTime? diaAnterior;
  Mensaje? anterior;
  var marcados = leidoHasta == null;
  for (final m in mensajes) {
    final local = m.createdAt.toLocal();
    final dia = DateTime(local.year, local.month, local.day);
    if (dia != diaAnterior) {
      filas.add(FilaDia(dia));
      diaAnterior = dia;
      anterior = null;
    }
    if (!marcados && m.autorId != miId && m.createdAt.isAfter(leidoHasta!)) {
      filas.add(const FilaNuevos());
      marcados = true;
      anterior = null;
    }
    final seguido = anterior != null &&
        anterior.autorId == m.autorId &&
        !anterior.borrado &&
        m.createdAt.difference(anterior.createdAt).inMinutes < 5;
    filas.add(FilaMensaje(m, seguido: seguido));
    anterior = m;
  }
  return filas;
}

/// "Hoy", "Ayer", "Lunes 3 de noviembre".
String tituloDia(DateTime dia, DateTime ahora) {
  const dias = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
  const meses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];
  final hoy = DateTime(ahora.year, ahora.month, ahora.day);
  final d = hoy.difference(dia).inDays;
  if (d == 0) return 'Hoy';
  if (d == 1) return 'Ayer';
  final base = '${dias[dia.weekday - 1]} ${dia.day} de ${meses[dia.month - 1]}';
  return dia.year == ahora.year ? base : '$base de ${dia.year}';
}

abstract interface class ChatRepository {
  /// Hasta [limite] mensajes anteriores a [antesDe] (del más nuevo al más viejo).
  Future<List<Mensaje>> pagina(String groupId, {DateTime? antesDe, int limite = 50});
  Future<Mensaje?> mensaje(String id);
  /// Devuelven el mensaje como quedó, para mostrarlo sin esperar al aviso en vivo.
  Future<Mensaje> enviar({required String groupId, String? texto, String? fileId, String? respondeA});
  Future<Mensaje> editar(String id, String texto);
  Future<void> borrar(String id);

  /// Hasta cuándo leí el chat del grupo (null si nunca lo abrí).
  Future<DateTime?> leidoHasta(String groupId);
  Future<void> marcarLeido(String groupId);

  /// Sin leer por grupo.
  Future<Map<String, int>> sinLeer();

  /// Archivos del grupo para adjuntar (id y nombre), por nombre.
  Future<List<({String id, String nombre})>> archivos(String groupId);

  /// Emite el id de cada mensaje nuevo o cambiado del grupo.
  Stream<String> cambios(String groupId);
}
