import 'file_item.dart';

/// Camino desde la raíz hasta la carpeta (para los breadcrumbs).
/// Devuelve `[]` para la raíz. Tolera ciclos o carpetas faltantes.
List<Folder> rutaHasta(String? folderId, Iterable<Folder> carpetas) {
  final porId = {for (final c in carpetas) c.id: c};
  final ruta = <Folder>[];
  final vistos = <String>{};
  var actual = folderId == null ? null : porId[folderId];
  while (actual != null && vistos.add(actual.id)) {
    ruta.add(actual);
    actual = actual.parentId == null ? null : porId[actual.parentId];
  }
  return ruta.reversed.toList();
}

/// Subcarpetas directas, ordenadas por nombre.
List<Folder> hijasDe(String? folderId, Iterable<Folder> carpetas) =>
    carpetas.where((c) => c.parentId == folderId).toList()
      ..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));

/// ¿Hay ya un archivo con ese nombre? (como en la base: sin distinguir mayúsculas)
FileItem? archivoConNombre(String nombre, Iterable<FileItem> archivos) {
  final buscado = nombre.trim().toLowerCase();
  for (final a in archivos) {
    if (a.nombre.toLowerCase() == buscado) return a;
  }
  return null;
}
