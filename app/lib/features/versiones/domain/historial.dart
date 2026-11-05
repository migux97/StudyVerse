import '../../calendario/domain/calendario.dart' show diasSemana, meses;
import '../../files/domain/file_item.dart';

/// Encabezado de cada día del historial: "Hoy", "Ayer", "Lunes 3 de
/// noviembre" (con el año si no es este).
String encabezadoDia(DateTime fecha, DateTime ahora) {
  final f = fecha.toLocal(), h = ahora.toLocal();
  final dia = DateTime(f.year, f.month, f.day);
  final hoy = DateTime(h.year, h.month, h.day);
  final dias = hoy.difference(dia).inDays;
  if (dias == 0) return 'Hoy';
  if (dias == 1) return 'Ayer';
  final base = '${diasSemana[f.weekday - 1]} ${f.day} de ${meses[f.month - 1]}';
  return f.year == h.year ? base : '$base de ${f.year}';
}

/// "14:05".
String horaCorta(DateTime fecha) {
  final f = fecha.toLocal();
  return '${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';
}

typedef DiaDeVersiones = ({String titulo, List<FileVersion> versiones});

/// Las versiones (de la más nueva a la más vieja) agrupadas por día.
List<DiaDeVersiones> agruparPorDia(List<FileVersion> versiones, DateTime ahora) {
  final dias = <DiaDeVersiones>[];
  for (final v in versiones) {
    final titulo = encabezadoDia(v.createdAt, ahora);
    if (dias.isNotEmpty && dias.last.titulo == titulo) {
      dias.last.versiones.add(v);
    } else {
      dias.add((titulo: titulo, versiones: [v]));
    }
  }
  return dias;
}

/// La versión visible anterior a [v] (para "Comparar con la anterior").
FileVersion? anteriorA(List<FileVersion> versiones, FileVersion v) {
  FileVersion? mejor;
  for (final x in versiones) {
    if (x.versionNumber < v.versionNumber && (mejor == null || x.versionNumber > mejor.versionNumber)) {
      mejor = x;
    }
  }
  return mejor;
}

/// "v8 · Entrega 1" o "v8".
String etiquetaVersion(FileVersion v) =>
    v.guardadaNombre == null ? 'v${v.versionNumber}' : 'v${v.versionNumber} · ${v.guardadaNombre}';
