class Folder {
  const Folder({
    required this.id,
    required this.groupId,
    this.parentId,
    required this.nombre,
    required this.createdAt,
  });

  final String id;
  final String groupId;
  final String? parentId;
  final String nombre;
  final DateTime createdAt;

  factory Folder.fromMap(Map<String, dynamic> map) => Folder(
        id: map['id'] as String,
        groupId: map['group_id'] as String,
        parentId: map['parent_id'] as String?,
        nombre: map['nombre'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}

class FileVersion {
  const FileVersion({
    required this.id,
    required this.fileId,
    required this.versionNumber,
    required this.storagePath,
    required this.sizeBytes,
    this.mimeType,
    this.nota,
    this.uploadedBy,
    this.uploaderNombre,
    required this.createdAt,
    this.guardadaNombre,
    this.guardadaPor,
    this.guardadaPorNombre,
    this.guardadaAt,
  });

  final String id;
  final String fileId;
  final int versionNumber;
  final String storagePath;
  final int sizeBytes;
  final String? mimeType;
  final String? nota;
  final String? uploadedBy;
  final String? uploaderNombre;
  final DateTime createdAt;

  /// Nombre con el que se guardó ("Entrega 1"), si se guardó. Las guardadas
  /// se ven siempre, aunque el plan gratis muestre solo las últimas.
  final String? guardadaNombre;
  final String? guardadaPor;
  final String? guardadaPorNombre;
  final DateTime? guardadaAt;

  bool get guardada => guardadaNombre != null;

  /// Una versión no cambia: alcanza con el id (sirve de clave en providers).
  @override
  bool operator ==(Object other) => other is FileVersion && other.id == id;

  @override
  int get hashCode => id.hashCode;

  /// Fila de `file_versions`, con `uploader:profiles(nombre)` embebido.
  factory FileVersion.fromMap(Map<String, dynamic> map) => FileVersion(
        id: map['id'] as String,
        fileId: map['file_id'] as String,
        versionNumber: map['version_number'] as int,
        storagePath: map['storage_path'] as String,
        sizeBytes: (map['size_bytes'] as num).toInt(),
        mimeType: map['mime_type'] as String?,
        nota: map['nota'] as String?,
        uploadedBy: map['uploaded_by'] as String?,
        uploaderNombre: (map['uploader'] as Map<String, dynamic>?)?['nombre'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        guardadaNombre: map['guardada_nombre'] as String?,
        guardadaPor: map['guardada_por'] as String?,
        guardadaPorNombre: (map['guardador'] as Map<String, dynamic>?)?['nombre'] as String?,
        guardadaAt: map['guardada_at'] == null ? null : DateTime.parse(map['guardada_at'] as String),
      );
}

class FileItem {
  const FileItem({
    required this.id,
    required this.groupId,
    this.folderId,
    required this.nombre,
    this.current,
    this.lockedBy,
    this.lockedByNombre,
    this.lockedAt,
    this.lockUntil,
    this.pedidos = const [],
    this.createdBy,
    required this.createdAt,
    this.deletedAt,
    this.deletedBy,
    this.deletedByNombre,
    this.grupo,
  });

  final String id;
  final String groupId;
  final String? folderId;
  final String nombre;
  final FileVersion? current;
  final String? lockedBy;
  final String? lockedByNombre;
  final DateTime? lockedAt;

  /// Hasta cuándo dura el bloqueo (elegido al bloquear).
  final DateTime? lockUntil;

  /// Quiénes le pidieron a quien lo edita que lo libere.
  final List<PedidoLiberacion> pedidos;
  final String? createdBy;
  final DateTime createdAt;

  /// Cuándo se mandó a la papelera (null si no está).
  final DateTime? deletedAt;
  final String? deletedBy;
  final String? deletedByNombre;

  /// Nombre del grupo (solo en búsquedas, destacados y recientes).
  final String? grupo;

  bool get enPapelera => deletedAt != null;

  /// Días que le quedan en la papelera antes de borrarse solo.
  int diasEnPapelera(DateTime ahora) =>
      deletedAt == null ? 0 : (diasPapelera - ahora.difference(deletedAt!).inDays).clamp(0, diasPapelera);

  FileKind get kind => fileKindFor(nombre);

  /// El nombre como se muestra (los documentos de StudyVerse sin extensión).
  String get visible => nombreVisible(nombre);

  /// Vence en `lock_until`; los bloqueos sin esa fecha, a las 24 h (como en la base).
  DateTime? get _venceEl => lockUntil ?? lockedAt?.add(duracionBloqueo);

  bool estaBloqueado(DateTime ahora) =>
      lockedBy != null && _venceEl != null && ahora.isBefore(_venceEl!);

  bool pedidoPor(String? userId) => pedidos.any((p) => p.requestedBy == userId);

  EstadoBloqueo estadoBloqueo(String? miId, DateTime ahora) {
    if (!estaBloqueado(ahora)) return EstadoBloqueo.libre;
    return lockedBy == miId ? EstadoBloqueo.mio : EstadoBloqueo.deOtro;
  }

  /// Cuánto le queda al bloqueo antes de vencer.
  Duration? vencimientoBloqueo(DateTime ahora) =>
      estaBloqueado(ahora) ? _venceEl!.difference(ahora) : null;

  /// Fila de `files`, con `current:file_versions(...)`, `locker:profiles(nombre)`
  /// y `pedidos:lock_requests(...)`.
  factory FileItem.fromMap(Map<String, dynamic> map) {
    final current = map['current'] as Map<String, dynamic>?;
    DateTime? fecha(String k) => map[k] == null ? null : DateTime.parse(map[k] as String);
    return FileItem(
      id: map['id'] as String,
      groupId: map['group_id'] as String,
      folderId: map['folder_id'] as String?,
      nombre: map['nombre'] as String,
      current: current == null ? null : FileVersion.fromMap(current),
      lockedBy: map['locked_by'] as String?,
      lockedByNombre: (map['locker'] as Map<String, dynamic>?)?['nombre'] as String?,
      lockedAt: fecha('locked_at'),
      lockUntil: fecha('lock_until'),
      pedidos: [
        for (final p in (map['pedidos'] as List? ?? const []))
          PedidoLiberacion.fromMap(p as Map<String, dynamic>),
      ],
      createdBy: map['created_by'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      deletedAt: fecha('deleted_at'),
      deletedBy: map['deleted_by'] as String?,
      deletedByNombre: (map['eliminador'] as Map<String, dynamic>?)?['nombre'] as String?,
      grupo: (map['grupo'] as Map<String, dynamic>?)?['nombre'] as String?,
    );
  }
}

/// Lo que está en la papelera se borra solo a los 30 días (como en Drive).
const diasPapelera = 30;

/// Un resultado de "Buscar en StudyVerse".
class ResultadoBusqueda {
  const ResultadoBusqueda({
    required this.fileId,
    required this.groupId,
    required this.grupo,
    this.folderId,
    this.carpeta,
    required this.nombre,
    required this.actualizado,
  });

  final String fileId;
  final String groupId;
  final String grupo;
  final String? folderId;
  final String? carpeta;
  final String nombre;
  final DateTime actualizado;

  FileKind get kind => fileKindFor(nombre);
  String get visible => nombreVisible(nombre);

  /// "Física II › Parciales".
  String get ubicacion => carpeta == null ? grupo : '$grupo › $carpeta';

  factory ResultadoBusqueda.fromMap(Map<String, dynamic> m) => ResultadoBusqueda(
        fileId: m['file_id'] as String,
        groupId: m['group_id'] as String,
        grupo: m['grupo'] as String,
        folderId: m['folder_id'] as String?,
        carpeta: m['carpeta'] as String?,
        nombre: m['nombre'] as String,
        actualizado: DateTime.parse(m['actualizado'] as String),
      );
}

/// "Ana necesita editar este archivo": pedido a quien lo tiene bloqueado.
class PedidoLiberacion {
  const PedidoLiberacion({required this.requestedBy, this.nombre, required this.createdAt});

  final String requestedBy;
  final String? nombre;
  final DateTime createdAt;

  factory PedidoLiberacion.fromMap(Map<String, dynamic> map) => PedidoLiberacion(
        requestedBy: map['requested_by'] as String,
        nombre: (map['requester'] as Map<String, dynamic>?)?['nombre'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}

/// Pedido que me llega en vivo (para avisarme aunque esté en otra pantalla).
class PedidoEntrante {
  const PedidoEntrante({
    required this.fileId,
    required this.groupId,
    required this.folderId,
    required this.archivo,
    required this.quien,
  });

  final String fileId;
  final String groupId;
  final String? folderId;
  final String archivo;
  final String quien;
}

/// Opciones de duración al bloquear.
enum DuracionBloqueo { dosHoras, hastaLaNoche, unDia }

/// Minutos que dura el bloqueo según la opción. "Hasta la noche" = hasta las
/// 23:59 de hoy (mínimo 2 h, por si ya es tarde).
int minutosDeBloqueo(DuracionBloqueo opcion, DateTime ahora) => switch (opcion) {
      DuracionBloqueo.dosHoras => 120,
      DuracionBloqueo.unDia => 24 * 60,
      DuracionBloqueo.hastaLaNoche => _minutosHastaLaNoche(ahora),
    };

int _minutosHastaLaNoche(DateTime ahora) {
  final noche = DateTime(ahora.year, ahora.month, ahora.day, 23, 59);
  final minutos = noche.difference(ahora).inMinutes;
  return minutos < 120 ? 120 : minutos;
}

const duracionBloqueo = Duration(hours: 24);

enum EstadoBloqueo { libre, mio, deOtro }

enum FileKind { studyverse, pdf, documento, planilla, presentacion, imagen, video, audio, comprimido, codigo, texto, otro }

const _extensiones = <FileKind, Set<String>>{
  FileKind.studyverse: {extensionDocumento},
  FileKind.pdf: {'pdf'},
  FileKind.documento: {'doc', 'docx', 'odt', 'rtf', 'pages'},
  FileKind.planilla: {'xls', 'xlsx', 'ods', 'csv', 'numbers'},
  FileKind.presentacion: {'ppt', 'pptx', 'odp', 'key'},
  FileKind.imagen: {'png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'bmp', 'heic'},
  FileKind.video: {'mp4', 'mov', 'avi', 'mkv', 'webm'},
  FileKind.audio: {'mp3', 'wav', 'ogg', 'm4a', 'flac'},
  FileKind.comprimido: {'zip', 'rar', '7z', 'tar', 'gz'},
  FileKind.codigo: {
    'dart', 'py', 'js', 'ts', 'java', 'c', 'cpp', 'h', 'cs', 'go', 'rs', 'php', 'rb',
    'html', 'css', 'json', 'xml', 'yaml', 'yml', 'sql', 'ipynb', 'm', 'r',
  },
  FileKind.texto: {'txt', 'md', 'tex'},
};

/// Extensión de los documentos de StudyVerse (no se muestra, como en Drive).
const extensionDocumento = 'svdoc';

/// "Informe.svdoc" → "Informe". El resto queda igual.
String nombreVisible(String nombre) =>
    nombre.toLowerCase().endsWith('.$extensionDocumento')
        ? nombre.substring(0, nombre.length - extensionDocumento.length - 1)
        : nombre;

FileKind fileKindFor(String nombre) {
  final punto = nombre.lastIndexOf('.');
  if (punto <= 0 || punto == nombre.length - 1) return FileKind.otro;
  final ext = nombre.substring(punto + 1).toLowerCase();
  for (final MapEntry(:key, :value) in _extensiones.entries) {
    if (value.contains(ext)) return key;
  }
  return FileKind.otro;
}

/// 1536 → "1,5 KB". Unidades de 1024, coma decimal.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const unidades = ['KB', 'MB', 'GB', 'TB'];
  var valor = bytes / 1024;
  var i = 0;
  while (valor >= 1024 && i < unidades.length - 1) {
    valor /= 1024;
    i++;
  }
  final texto = valor >= 100 || valor == valor.roundToDouble()
      ? valor.round().toString()
      : valor.toStringAsFixed(1).replaceAll('.', ',');
  return '$texto ${unidades[i]}';
}

/// "se libera en 23 h" / "se libera en 40 min".
String formatearVencimiento(Duration resta) {
  if (resta.inMinutes < 60) return 'se libera en ${resta.inMinutes < 1 ? 1 : resta.inMinutes} min';
  return 'se libera en ${resta.inHours} h';
}

const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

/// "recién", "hace 5 min", "hace 3 h", "ayer", "12 mar", "12 mar 2025".
String formatearFecha(DateTime fecha, DateTime ahora) {
  final local = fecha.toLocal();
  final hoy = ahora.toLocal();
  final diff = hoy.difference(local);
  if (diff.inMinutes < 1) return 'recién';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24 && local.day == hoy.day) return 'hace ${diff.inHours} h';
  final ayer = DateTime(hoy.year, hoy.month, hoy.day).subtract(const Duration(days: 1));
  if (!local.isBefore(ayer)) return 'ayer';
  final base = '${local.day} ${_meses[local.month - 1]}';
  return local.year == hoy.year ? base : '$base ${local.year}';
}
