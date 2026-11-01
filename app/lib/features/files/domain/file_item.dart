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
    this.createdBy,
    required this.createdAt,
  });

  final String id;
  final String groupId;
  final String? folderId;
  final String nombre;
  final FileVersion? current;
  final String? lockedBy;
  final String? lockedByNombre;
  final DateTime? lockedAt;
  final String? createdBy;
  final DateTime createdAt;

  FileKind get kind => fileKindFor(nombre);

  /// Bloqueo vigente (los bloqueos vencen a las 24 h).
  bool estaBloqueado(DateTime ahora) =>
      lockedBy != null &&
      lockedAt != null &&
      ahora.difference(lockedAt!) < const Duration(hours: 24);

  /// Fila de `files`, con `current:file_versions(...)` y `locker:profiles(nombre)`.
  factory FileItem.fromMap(Map<String, dynamic> map) {
    final current = map['current'] as Map<String, dynamic>?;
    return FileItem(
      id: map['id'] as String,
      groupId: map['group_id'] as String,
      folderId: map['folder_id'] as String?,
      nombre: map['nombre'] as String,
      current: current == null ? null : FileVersion.fromMap(current),
      lockedBy: map['locked_by'] as String?,
      lockedByNombre: (map['locker'] as Map<String, dynamic>?)?['nombre'] as String?,
      lockedAt: map['locked_at'] == null ? null : DateTime.parse(map['locked_at'] as String),
      createdBy: map['created_by'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

enum FileKind { pdf, documento, planilla, presentacion, imagen, video, audio, comprimido, codigo, texto, otro }

const _extensiones = <FileKind, Set<String>>{
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
