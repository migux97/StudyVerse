import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Guarda un archivo en el dispositivo: en la web lo descarga; en Android
/// abre el "Guardar como" del sistema. Devuelve false si se canceló.
Future<bool> guardarEnDispositivo(Uint8List bytes, String nombre, String mime) async {
  final uri = await FilePicker.saveFile(fileName: nombre, bytes: bytes, mimeType: mime);
  // En la web no hay diálogo: se descarga y no devuelve ruta.
  return kIsWeb || uri != null;
}

const mimeDocx = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
const mimePdf = 'application/pdf';
