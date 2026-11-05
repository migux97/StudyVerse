import 'package:flutter_test/flutter_test.dart';
import 'package:studyverse/features/calendario/domain/calendario.dart';
import 'package:studyverse/features/comentarios/domain/comentario.dart';
import 'package:studyverse/features/files/domain/file_item.dart';

FechaCalendario _f(String titulo, DateTime dia, {TipoFecha tipo = TipoFecha.tarea, String? hora, bool hecha = false}) =>
    FechaCalendario(id: titulo, tipo: tipo, titulo: titulo, dia: dia, hora: hora, groupId: 'g', grupo: 'TP', hecha: hecha);

void main() {
  group('Calendario', () {
    final hoy = DateTime(2026, 11, 12); // jueves

    test('la grilla del mes va de lunes a domingo', () {
      final dias = diasDeLaGrilla(DateTime(2026, 11));
      expect(dias.first, DateTime(2026, 10, 26), reason: 'el lunes antes del 1 de noviembre');
      expect(dias.last, DateTime(2026, 12, 6));
      expect(dias.length % 7, 0);
    });

    test('agrupa por día y ordena por hora (sin hora al final)', () {
      final m = porDia([
        _f('Sin hora', DateTime(2026, 11, 14)),
        _f('Tarde', DateTime(2026, 11, 14), hora: '18:00'),
        _f('Mañana', DateTime(2026, 11, 14), hora: '08:30'),
      ]);
      expect(m[DateTime(2026, 11, 14)]!.map((f) => f.titulo), ['Mañana', 'Tarde', 'Sin hora']);
    });

    test('lo que viene: la próxima semana, sin tareas hechas ni pasadas', () {
      final l = proximas([
        _f('Ayer', DateTime(2026, 11, 11)),
        _f('Hecha', DateTime(2026, 11, 13), hecha: true),
        _f('Parcial', DateTime(2026, 11, 16), tipo: TipoFecha.parcial),
        _f('Hoy', DateTime(2026, 11, 12)),
        _f('Lejos', DateTime(2026, 11, 30)),
      ], hoy);
      expect(l.map((f) => f.titulo), ['Hoy', 'Parcial']);
    });

    test('cuándo es, en palabras', () {
      expect(cuandoEs(DateTime(2026, 11, 12), hoy), 'Hoy');
      expect(cuandoEs(DateTime(2026, 11, 13), hoy), 'Mañana');
      expect(cuandoEs(DateTime(2026, 11, 16), hoy), 'Lunes 16');
      expect(cuandoEs(DateTime(2026, 12, 3), hoy), '3 dic');
    });

    test('lee tareas y eventos de la base', () {
      final t = FechaCalendario.deTarea({
        'id': 't', 'titulo': 'Intro', 'due_date': '2026-11-20', 'estado': 'hecha', 'group_id': 'g',
        'grupo': {'nombre': 'Física II'},
      });
      expect((t.tipo, t.hecha, t.grupo), (TipoFecha.tarea, true, 'Física II'));
      final e = FechaCalendario.deEvento({
        'id': 'e', 'titulo': 'Parcial', 'tipo': 'parcial', 'fecha': '2026-11-18', 'hora': '14:30:00',
        'group_id': 'g', 'grupo': {'nombre': 'Física II'},
      });
      expect((e.tipo, e.hora), (TipoFecha.parcial, '14:30'));
    });
  });

  group('Comentarios', () {
    test('separa las menciones del resto del texto', () {
      expect(partesDelTexto('Hola @ana.lopez, mirá esto'), [
        (texto: 'Hola ', mencion: false),
        (texto: '@ana.lopez', mencion: true),
        (texto: ', mirá esto', mencion: false),
      ]);
      expect(partesDelTexto('sin menciones'), [(texto: 'sin menciones', mencion: false)]);
    });

    test('detecta la mención que se está escribiendo', () {
      expect(mencionEnCurso('Hola @an', 8), (buscado: 'an', inicio: 5));
      expect(mencionEnCurso('@', 1), (buscado: '', inicio: 0));
      expect(mencionEnCurso('mail@uni.edu', 12), isNull, reason: 'un email no es una mención');
      expect(mencionEnCurso('Hola @ana y', 11), isNull, reason: 'el cursor ya pasó la mención');
    });

    test('completa la mención y deja el cursor después', () {
      final r = completarMencion('Hola @an y chau', 5, 8, 'ana.lopez');
      expect(r.texto, 'Hola @ana.lopez  y chau');
      expect(r.cursor, 16);
    });
  });

  group('Búsqueda y papelera', () {
    test('ubicación del resultado: grupo › carpeta', () {
      final r = ResultadoBusqueda.fromMap({
        'file_id': 'f', 'group_id': 'g', 'grupo': 'Física II', 'folder_id': 'c', 'carpeta': 'Parciales',
        'nombre': 'Resumen.svdoc', 'actualizado': '2026-11-01T10:00:00Z',
      });
      expect(r.ubicacion, 'Física II › Parciales');
      expect(r.visible, 'Resumen');
      expect(r.kind, FileKind.studyverse);
    });

    test('días que le quedan en la papelera', () {
      final a = FileItem(
        id: 'f',
        groupId: 'g',
        nombre: 'x.pdf',
        createdAt: DateTime(2026),
        deletedAt: DateTime(2026, 11, 1),
      );
      expect(a.enPapelera, isTrue);
      expect(a.diasEnPapelera(DateTime(2026, 11, 11)), 20);
      expect(a.diasEnPapelera(DateTime(2027)), 0);
    });
  });
}
