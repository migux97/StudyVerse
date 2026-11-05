import '../../groups/domain/group.dart';

enum EstadoTarea {
  pendiente('Pendiente'),
  enProgreso('En progreso'),

  /// Lista, esperando que un admin la apruebe (si el grupo lo pide).
  entregada('Entregada'),
  hecha('Hecha');

  const EstadoTarea(this.etiqueta);
  final String etiqueta;

  /// Valor en la base (`estado_tarea`).
  String get valor => this == enProgreso ? 'en_progreso' : name;

  static EstadoTarea desde(String valor) =>
      valor == 'en_progreso' ? enProgreso : EstadoTarea.values.byName(valor);
}

class Task {
  const Task({
    required this.id,
    required this.groupId,
    this.folderId,
    this.folderNombre,
    required this.titulo,
    this.assignedTo,
    this.assignedNombre,
    this.dueDate,
    this.estado = EstadoTarea.pendiente,
    this.completedAt,
    this.createdBy,
    required this.createdAt,
    this.entregadaPor,
    this.entregadaPorNombre,
    this.entregadaAt,
    this.entregaNota,
    this.revisionNota,
  });

  final String id;
  final String groupId;
  final String? folderId;
  final String? folderNombre;
  final String titulo;
  final String? assignedTo;
  final String? assignedNombre;

  /// Solo fecha (sin hora), en la zona del usuario.
  final DateTime? dueDate;
  final EstadoTarea estado;
  final DateTime? completedAt;
  final String? createdBy;
  final DateTime createdAt;

  /// Quién la entregó, cuándo y qué dejó dicho.
  final String? entregadaPor;
  final String? entregadaPorNombre;
  final DateTime? entregadaAt;
  final String? entregaNota;

  /// Lo que pidió cambiar un admin (hasta que se vuelva a entregar).
  final String? revisionNota;

  bool get hecha => estado == EstadoTarea.hecha;
  bool get entregada => estado == EstadoTarea.entregada;

  /// Fila de `tasks`, con `assignee:profiles(nombre)` y `folder:folders(nombre)`.
  factory Task.fromMap(Map<String, dynamic> map) => Task(
        id: map['id'] as String,
        groupId: map['group_id'] as String,
        folderId: map['folder_id'] as String?,
        folderNombre: (map['folder'] as Map<String, dynamic>?)?['nombre'] as String?,
        titulo: map['titulo'] as String,
        assignedTo: map['assigned_to'] as String?,
        assignedNombre: (map['assignee'] as Map<String, dynamic>?)?['nombre'] as String?,
        dueDate: map['due_date'] == null ? null : DateTime.parse(map['due_date'] as String),
        estado: EstadoTarea.desde(map['estado'] as String),
        completedAt: map['completed_at'] == null ? null : DateTime.parse(map['completed_at'] as String),
        createdBy: map['created_by'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        entregadaPor: map['entregada_por'] as String?,
        entregadaPorNombre: (map['entregador'] as Map<String, dynamic>?)?['nombre'] as String?,
        entregadaAt: map['entregada_at'] == null ? null : DateTime.parse(map['entregada_at'] as String),
        entregaNota: map['entrega_nota'] as String?,
        revisionNota: map['revision_nota'] as String?,
      );
}

/// Aviso en vivo a quien entregó: un admin aprobó su tarea o pidió cambios.
class Revision {
  const Revision({
    required this.taskId,
    required this.titulo,
    required this.groupId,
    required this.aprobada,
    required this.por,
  });

  final String taskId;
  final String titulo;
  final String groupId;
  final bool aprobada;
  final String por;

  /// Fila de `tasks` releída después del aviso, con `revisor:profiles(nombre)`.
  factory Revision.fromMap(Map<String, dynamic> m) => Revision(
        taskId: m['id'] as String,
        titulo: m['titulo'] as String? ?? 'tu tarea',
        groupId: m['group_id'] as String,
        aprobada: m['estado'] == 'hecha',
        por: (m['revisor'] as Map<String, dynamic>?)?['nombre'] as String? ?? 'Un admin',
      );

  String get mensaje => aprobada ? '$por aprobó «$titulo»' : '$por te pidió cambios en «$titulo»';
}

/// Datos editables de una tarea (crear o editar).
class TaskDraft {
  const TaskDraft({
    required this.titulo,
    this.assignedTo,
    this.dueDate,
    this.folderId,
    this.estado = EstadoTarea.pendiente,
  });

  final String titulo;
  final String? assignedTo;
  final DateTime? dueDate;
  final String? folderId;
  final EstadoTarea estado;

  Map<String, dynamic> toMap() => {
        'titulo': titulo.trim(),
        'assigned_to': assignedTo,
        'due_date': dueDate == null ? null : _soloFecha(dueDate!),
        'folder_id': folderId,
        'estado': estado.valor,
      };
}

String _soloFecha(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Cómo mostrar la fecha límite. [atrasada] si ya pasó y la tarea no está hecha.
({String texto, bool atrasada, bool pronto}) describirVencimiento(Task t, DateTime ahora) {
  final due = t.dueDate!;
  final hoy = DateTime(ahora.year, ahora.month, ahora.day);
  final dias = DateTime(due.year, due.month, due.day).difference(hoy).inDays;
  const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  final fecha = '${due.day} ${meses[due.month - 1]}';

  if (t.hecha) return (texto: fecha, atrasada: false, pronto: false);
  return switch (dias) {
    < -1 => (texto: 'Venció hace ${-dias} días', atrasada: true, pronto: false),
    -1 => (texto: 'Venció ayer', atrasada: true, pronto: false),
    0 => (texto: 'Vence hoy', atrasada: false, pronto: true),
    1 => (texto: 'Vence mañana', atrasada: false, pronto: true),
    < 7 => (texto: 'Vence en $dias días', atrasada: false, pronto: false),
    _ => (texto: 'Vence el $fecha', atrasada: false, pronto: false),
  };
}

/// Orden dentro de cada estado: primero las que vencen antes; sin fecha, al final.
List<Task> ordenarTareas(Iterable<Task> tareas) => tareas.toList()
  ..sort((a, b) {
    if (a.hecha && b.hecha) {
      return (b.completedAt ?? b.createdAt).compareTo(a.completedAt ?? a.createdAt);
    }
    final fa = a.dueDate, fb = b.dueDate;
    if (fa == null && fb == null) return a.createdAt.compareTo(b.createdAt);
    if (fa == null) return 1;
    if (fb == null) return -1;
    return fa.compareTo(fb);
  });

/// Aporte de un integrante (vista "Aportes").
class Aporte {
  const Aporte({
    required this.userId,
    required this.nombre,
    this.avatarUrl,
    required this.rol,
    required this.tareasCompletadas,
    required this.tareasPendientes,
    required this.versionesSubidas,
    this.ultimaActividad,
  });

  final String userId;
  final String nombre;
  final String? avatarUrl;
  final GroupRole rol;
  final int tareasCompletadas;
  final int tareasPendientes;
  final int versionesSubidas;
  final DateTime? ultimaActividad;

  factory Aporte.fromMap(Map<String, dynamic> map) => Aporte(
        userId: map['user_id'] as String,
        nombre: map['nombre'] as String,
        avatarUrl: map['avatar_url'] as String?,
        rol: GroupRole.values.byName(map['rol'] as String),
        tareasCompletadas: (map['tareas_completadas'] as num).toInt(),
        tareasPendientes: (map['tareas_pendientes'] as num).toInt(),
        versionesSubidas: (map['versiones_subidas'] as num).toInt(),
        ultimaActividad: map['ultima_actividad'] == null
            ? null
            : DateTime.parse(map['ultima_actividad'] as String),
      );
}
