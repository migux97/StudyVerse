import 'package:flutter/material.dart';

import '../domain/file_item.dart';

/// Ícono y color según el tipo de archivo, al estilo de Drive.
class FileIcon extends StatelessWidget {
  const FileIcon({super.key, required this.kind, this.size = 28});
  final FileKind kind;
  final double size;

  static (IconData, Color) estilo(FileKind kind) => switch (kind) {
        FileKind.studyverse => (Icons.article_rounded, const Color(0xFF1C8AD4)),
        FileKind.pdf => (Icons.picture_as_pdf_rounded, const Color(0xFFE5483B)),
        FileKind.documento => (Icons.description_rounded, const Color(0xFF3B78E7)),
        FileKind.planilla => (Icons.table_chart_rounded, const Color(0xFF1E9E5A)),
        FileKind.presentacion => (Icons.slideshow_rounded, const Color(0xFFF2A60C)),
        FileKind.imagen => (Icons.image_rounded, const Color(0xFFD14B8F)),
        FileKind.video => (Icons.movie_rounded, const Color(0xFF8E5BD8)),
        FileKind.audio => (Icons.audiotrack_rounded, const Color(0xFF0E9AA7)),
        FileKind.comprimido => (Icons.folder_zip_rounded, const Color(0xFF8D6E63)),
        FileKind.codigo => (Icons.code_rounded, const Color(0xFF546E7A)),
        FileKind.texto => (Icons.article_rounded, const Color(0xFF607D8B)),
        FileKind.otro => (Icons.insert_drive_file_rounded, const Color(0xFF78909C)),
      };

  @override
  Widget build(BuildContext context) {
    final (icono, color) = estilo(kind);
    return Icon(icono, color: color, size: size);
  }
}
