import 'package:flutter_test/flutter_test.dart';
import 'package:studyverse/features/chat/domain/mensaje.dart';
import 'package:studyverse/features/notificaciones/domain/notificacion.dart';

Mensaje m(String id, String autor, DateTime cuando, {bool borrado = false}) => Mensaje(
      id: id,
      groupId: 'g',
      autorId: autor,
      texto: borrado ? null : 'hola',
      createdAt: cuando,
      borradoAt: borrado ? cuando : null,
    );

void main() {
  test('lee un mensaje con autor, archivo y cita', () {
    final x = Mensaje.fromMap({
      'id': 'm2',
      'group_id': 'g',
      'autor': 'b',
      'autor_perfil': {'id': 'b', 'nombre': 'Beto', 'created_at': '2026-11-01T00:00:00Z'},
      'texto': 'Dale',
      'file_id': 'f',
      'archivo': {'nombre': 'Informe.svdoc'},
      'respondido': {'id': 'm1', 'texto': 'Hola', 'borrado_at': null, 'autor_perfil': {'nombre': 'Ana'}},
      'created_at': '2026-11-06T12:00:00Z',
      'editado_at': '2026-11-06T12:01:00Z',
      'borrado_at': null,
    });
    expect(x.autor?.nombre, 'Beto');
    expect(x.archivoNombre, 'Informe.svdoc');
    expect(x.cita?.autorNombre, 'Ana');
    expect(x.editado, isTrue);
  });

  test('armarFilas: días, mensajes seguidos y la marca de nuevos', () {
    final base = DateTime(2026, 11, 5, 10);
    final filas = armarFilas([
      m('1', 'ana', base),
      m('2', 'ana', base.add(const Duration(minutes: 2))),
      m('3', 'ana', base.add(const Duration(minutes: 20))),
      m('4', 'beto', base.add(const Duration(days: 1))),
      m('5', 'yo', base.add(const Duration(days: 1, minutes: 1))),
    ], leidoHasta: base.add(const Duration(hours: 1)), miId: 'yo');

    expect(filas.map((f) => f.runtimeType.toString()).toList(),
        ['FilaDia', 'FilaMensaje', 'FilaMensaje', 'FilaMensaje', 'FilaDia', 'FilaNuevos', 'FilaMensaje', 'FilaMensaje']);
    final mensajes = filas.whereType<FilaMensaje>().toList();
    expect(mensajes[1].seguido, isTrue, reason: 'mismo autor a 2 minutos');
    expect(mensajes[2].seguido, isFalse, reason: 'a 20 minutos ya no');
    expect(mensajes[4].seguido, isFalse, reason: 'otro autor');
  });

  test('mis mensajes no ponen la marca de nuevos', () {
    final base = DateTime(2026, 11, 5, 10);
    final filas = armarFilas([m('1', 'yo', base)], leidoHasta: DateTime(2026), miId: 'yo');
    expect(filas.whereType<FilaNuevos>(), isEmpty);
  });

  test('títulos de día', () {
    final ahora = DateTime(2026, 11, 6, 15);
    expect(tituloDia(DateTime(2026, 11, 6), ahora), 'Hoy');
    expect(tituloDia(DateTime(2026, 11, 5), ahora), 'Ayer');
    expect(tituloDia(DateTime(2026, 11, 2), ahora), 'Lunes 2 de noviembre');
  });

  test('una notificación de chat (o de un tipo nuevo) no rompe la campanita', () {
    expect(TipoNotificacion.desde('chat'), TipoNotificacion.chat);
    expect(TipoNotificacion.desde('algo_nuevo'), TipoNotificacion.aviso);
  });
}
