import 'package:flutter_test/flutter_test.dart';
import 'package:studyverse/features/activity/domain/activity_item.dart';

ActivityItem _evento(String tipo, Map<String, dynamic> payload, {String userId = 'juan'}) => ActivityItem(
      id: 'e',
      groupId: 'g',
      userId: userId,
      actorNombre: userId == 'juan' ? 'Juan' : 'Ana',
      tipo: tipo,
      payload: payload,
      createdAt: DateTime(2026, 11, 1, 12),
    );

String _texto(ActivityItem e, {String? miId}) {
  final (:actor, :accion) = describirActividad(e, miId: miId);
  return '$actor $accion';
}

void main() {
  group('textos del feed', () {
    test('versiones', () {
      expect(_texto(_evento('version_subida', {'nombre': 'Informe.docx', 'version': 3})),
          'Juan subió la v3 de Informe.docx');
      expect(_texto(_evento('version_subida', {'nombre': 'Informe.docx', 'version': 1})),
          'Juan subió Informe.docx');
      expect(_texto(_evento('version_restaurada', {'nombre': 'Informe.docx', 'version': 4, 'desde': 1})),
          'Juan restauró la v1 de Informe.docx (ahora es la v4)');
    });

    test('tareas', () {
      expect(_texto(_evento('tarea_completada', {'titulo': 'Conclusión'})), 'Juan completó la tarea "Conclusión"');
      expect(_texto(_evento('tarea_creada', {'titulo': 'Intro', 'a': 'Ana'})), 'Juan creó la tarea "Intro" para Ana');
    });

    test('bloqueos', () {
      expect(_texto(_evento('archivo_bloqueado', {'nombre': 'Informe.docx'})), 'Juan está editando Informe.docx');
      expect(_texto(_evento('desbloqueo_forzado', {'nombre': 'Informe.docx', 'de': 'Caro'})),
          'Juan desbloqueó Informe.docx, que estaba editando Caro');
      expect(_texto(_evento('liberacion_pedida', {'nombre': 'Informe.docx', 'a': 'Caro'})),
          'Juan le pidió Informe.docx a Caro');
    });

    test('integrantes', () {
      expect(_texto(_evento('miembro_unido', {})), 'Juan se unió al grupo');
      expect(_texto(_evento('miembro_salio', {'por': 'Ana'})), 'Juan fue quitado del grupo por Ana');
    });

    test('en segunda persona si fui yo (voseo)', () {
      expect(_texto(_evento('version_subida', {'nombre': 'a.pdf', 'version': 2}), miId: 'juan'),
          'Vos subiste la v2 de a.pdf');
      expect(_texto(_evento('miembro_unido', {}), miId: 'juan'), 'Vos te uniste al grupo');
      expect(_texto(_evento('archivo_bloqueado', {'nombre': 'a.pdf'}), miId: 'juan'), 'Vos estás editando a.pdf');
    });

    test('telegram', () {
      expect(_texto(_evento('telegram_vinculado', {'chat': 'TP Bio'})),
          'Juan conectó el chat de Telegram "TP Bio"');
    });

    test('tipo desconocido no rompe', () {
      expect(_texto(_evento('algo_nuevo', {})), 'Juan hizo un cambio');
    });
  });

  test('encabezados por día', () {
    final ahora = DateTime(2026, 11, 4, 10); // miércoles
    expect(encabezadoDia(DateTime(2026, 11, 4, 8), ahora), 'Hoy');
    expect(encabezadoDia(DateTime(2026, 11, 3, 23), ahora), 'Ayer');
    expect(encabezadoDia(DateTime(2026, 11, 2, 9), ahora), 'Lunes 2 de noviembre');
    expect(encabezadoDia(DateTime(2025, 11, 2, 9), ahora), 'Domingo 2 de noviembre de 2025');
  });

  test('evento desde la base', () {
    final e = ActivityItem.fromMap({
      'id': 'e1',
      'group_id': 'g',
      'user_id': 'u',
      'actor': {'nombre': 'Ana'},
      'tipo': 'version_subida',
      'payload': {'file_id': 'f', 'folder_id': 'c', 'nombre': 'a.pdf', 'version': 2},
      'created_at': '2026-11-01T12:00:00Z',
    });
    expect(e.actorNombre, 'Ana');
    expect(e.esDeArchivo, isTrue);
    expect(e.folderId, 'c');
  });
}
