import '../../../core/errors.dart';

class ActivityFailure extends AppFailure {
  const ActivityFailure(super.mensaje);
}

/// Un evento del feed del grupo (lo escriben los triggers de la base).
class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.groupId,
    this.userId,
    this.actorNombre,
    required this.tipo,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final String groupId;
  final String? userId;
  final String? actorNombre;
  final String tipo;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  /// Carpeta del archivo/carpeta del evento, para ir a verlo (null = raíz).
  String? get folderId => payload['folder_id'] as String?;
  bool get esDeArchivo => payload.containsKey('file_id');

  factory ActivityItem.fromMap(Map<String, dynamic> map) => ActivityItem(
        id: map['id'] as String,
        groupId: map['group_id'] as String,
        userId: map['user_id'] as String?,
        actorNombre: (map['actor'] as Map<String, dynamic>?)?['nombre'] as String?,
        tipo: map['tipo'] as String,
        payload: (map['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}

/// Quién y qué, por separado para poder resaltar al actor:
/// ("Juan", "subió la v3 de Informe.docx").
({String actor, String accion}) describirActividad(ActivityItem a, {String? miId}) {
  final soyYo = a.userId != null && a.userId == miId;
  final actor = soyYo ? 'Vos' : (a.actorNombre ?? 'Alguien');
  final p = a.payload;
  final nombre = p['nombre'] as String? ?? '';
  final titulo = p['titulo'] as String? ?? '';
  final para = p['a'] as String?;

  // Algunos verbos cambian con "vos" (voseo): "te uniste", "saliste".
  String v(String el, String vos) => soyYo ? vos : el;

  final accion = switch (a.tipo) {
    'version_subida' when p['version'] == 1 => '${v('subió', 'subiste')} $nombre',
    'version_subida' => '${v('subió', 'subiste')} la v${p['version']} de $nombre',
    'version_restaurada' => '${v('restauró', 'restauraste')} la v${p['desde']} de $nombre (ahora es la v${p['version']})',
    'archivo_bloqueado' => '${v('está', 'estás')} editando $nombre',
    'archivo_desbloqueado' => '${v('terminó', 'terminaste')} de editar $nombre',
    'desbloqueo_forzado' => '${v('desbloqueó', 'desbloqueaste')} $nombre, que estaba editando ${p['de'] ?? 'otra persona'}',
    'archivo_renombrado' => '${v('renombró', 'renombraste')} ${p['antes']} a $nombre',
    'archivo_eliminado' => '${v('eliminó', 'eliminaste')} $nombre',
    'archivo_a_papelera' => '${v('mandó', 'mandaste')} $nombre a la papelera',
    'archivo_restaurado' => '${v('restauró', 'restauraste')} $nombre de la papelera',
    'comentario' => '${v('comentó', 'comentaste')} en $nombre',
    'evento_creado' => '${v('agregó', 'agregaste')} ${p['titulo']} al calendario',
    'carpeta_creada' => '${v('creó', 'creaste')} la carpeta $nombre',
    'miembro_unido' => v('se unió al grupo', 'te uniste al grupo'),
    'curso_sumado' => '${v('sumó', 'sumaste')} el grupo al curso "${p['curso'] ?? ''}"',
    'curso_quitado' => '${v('quitó', 'quitaste')} el grupo del curso "${p['curso'] ?? ''}"',
    'miembro_salio' when p['por'] != null => v('fue quitado del grupo por ${p['por']}', 'fuiste quitado del grupo por ${p['por']}'),
    'miembro_salio' => v('salió del grupo', 'saliste del grupo'),
    'tarea_creada' when para != null => '${v('creó', 'creaste')} la tarea "$titulo" para $para',
    'tarea_creada' => '${v('creó', 'creaste')} la tarea "$titulo"',
    'tarea_completada' => '${v('completó', 'completaste')} la tarea "$titulo"',
    'tarea_entregada' => '${v('entregó', 'entregaste')} la tarea "$titulo"',
    'tarea_aprobada' when para != null => '${v('aprobó', 'aprobaste')} "$titulo" de $para',
    'tarea_aprobada' => '${v('aprobó', 'aprobaste')} la tarea "$titulo"',
    'tarea_cambios_pedidos' when para != null => '${v('le pidió', 'le pediste')} cambios a $para en "$titulo"',
    'tarea_cambios_pedidos' => '${v('pidió', 'pediste')} cambios en "$titulo"',
    'tarea_asignada' => '${v('asignó', 'asignaste')} "$titulo" a $para',
    'liberacion_pedida' => '${v('le pidió', 'le pediste')} $nombre a ${para ?? 'quien lo editaba'}',
    'telegram_vinculado' => '${v('conectó', 'conectaste')} el chat de Telegram "${p['chat']}"',
    _ => v('hizo un cambio', 'hiciste un cambio'),
  };
  return (actor: actor, accion: accion);
}

/// Encabezado de cada día en el feed: "Hoy", "Ayer", "Lunes 3 de noviembre".
String encabezadoDia(DateTime fecha, DateTime ahora) {
  final d = DateTime(fecha.toLocal().year, fecha.toLocal().month, fecha.toLocal().day);
  final hoy = DateTime(ahora.year, ahora.month, ahora.day);
  final dias = hoy.difference(d).inDays;
  if (dias == 0) return 'Hoy';
  if (dias == 1) return 'Ayer';
  const semana = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
  const meses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];
  final base = '${semana[d.weekday - 1]} ${d.day} de ${meses[d.month - 1]}';
  return d.year == hoy.year ? base : '$base de ${d.year}';
}
