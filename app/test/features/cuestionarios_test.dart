import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyverse/features/cuestionarios/domain/cuestionario.dart';
import 'package:studyverse/features/cuestionarios/domain/exportar_resultados.dart';
import 'package:studyverse/features/cuestionarios/presentation/detector_salidas.dart';

class _TimerFalso implements Timer {
  _TimerFalso(this.callback);
  final void Function() callback;
  bool cancelado = false;
  bool disparado = false;

  void disparar() {
    if (cancelado) return;
    disparado = true;
    callback();
  }

  @override
  void cancel() => cancelado = true;
  @override
  bool get isActive => !cancelado && !disparado;
  @override
  int get tick => 0;
}

class _Banco {
  _Banco({required bool esWeb}) {
    detector = DetectorSalidas(
      esWeb: esWeb,
      gracia: const Duration(seconds: 2),
      reloj: () => ahora,
      crearTimer: (d, cb) {
        final t = _TimerFalso(cb);
        timers.add(t);
        return t;
      },
      alSalir: () => salidas++,
      alVolver: volvio.add,
    );
  }

  late final DetectorSalidas detector;
  DateTime ahora = DateTime.utc(2026, 11, 1, 10);
  int salidas = 0;
  final volvio = <Duration>[];
  final timers = <_TimerFalso>[];

  void pasan(int segundos) => ahora = ahora.add(Duration(seconds: segundos));
  void cambio(AppLifecycleState e) => detector.cambio(e);
}

Map<String, dynamic> _cuestionarioMap({String? publicado = '2026-11-01T00:00:00Z', String resultados = 'al_cerrar'}) => {
      'id': 'q1',
      'curso_id': 'c1',
      'titulo': 'Parcial',
      'descripcion': null,
      'abre_at': '2026-11-10T10:00:00Z',
      'cierra_at': '2026-11-10T12:00:00Z',
      'duracion_min': 30,
      'intentos': 2,
      'resultados': resultados,
      'mezclar': true,
      'tope_salidas': 3,
      'nota_maxima': 10,
      'publicado_at': publicado,
    };

Map<String, dynamic> _intentoMap({
  String id = 'i1',
  String? entregado = '2026-11-10T10:20:00Z',
  num? nota,
  int numero = 1,
}) =>
    {
      'id': id,
      'cuestionario_id': 'q1',
      'user_id': 'u1',
      'numero': numero,
      'empezado_at': '2026-11-10T10:00:00Z',
      'vence_at': '2026-11-10T10:30:00Z',
      'entregado_at': entregado,
      'nota': nota,
    };

Intento _intento(int numero, {bool entregado = true, num? nota, int salidas = 0, int afuera = 0}) =>
    Intento.fromMap({
      ..._intentoMap(id: 'i$numero', numero: numero, entregado: entregado ? '2026-11-10T10:20:00Z' : null, nota: nota),
      'salidas': salidas,
      'segundos_afuera': afuera,
    });

void main() {
  group('DetectorSalidas en celular', () {
    test('paused avisa una salida y resumed la vuelta con la duración', () {
      final b = _Banco(esWeb: false);
      b.cambio(AppLifecycleState.paused);
      expect(b.salidas, 1);
      expect(b.detector.afuera, isTrue);
      b.pasan(45);
      b.cambio(AppLifecycleState.resumed);
      expect(b.volvio, [const Duration(seconds: 45)]);
      expect(b.detector.afuera, isFalse);
    });

    test('hidden también cuenta como salida', () {
      final b = _Banco(esWeb: false);
      b.cambio(AppLifecycleState.hidden);
      expect(b.salidas, 1);
    });

    test('inactive solo no cuenta ni crea timers', () {
      final b = _Banco(esWeb: false);
      b.cambio(AppLifecycleState.inactive);
      b.pasan(60);
      b.cambio(AppLifecycleState.resumed);
      expect(b.salidas, 0);
      expect(b.volvio, isEmpty);
      expect(b.timers, isEmpty);
    });

    test('hidden y paused repetidos no cuentan doble', () {
      final b = _Banco(esWeb: false);
      b.cambio(AppLifecycleState.hidden);
      b.cambio(AppLifecycleState.hidden);
      b.cambio(AppLifecycleState.paused);
      expect(b.salidas, 1);
    });

    test('resumed sin haber salido no avisa la vuelta', () {
      final b = _Banco(esWeb: false);
      b.cambio(AppLifecycleState.resumed);
      expect(b.volvio, isEmpty);
    });

    test('después de volver, una salida nueva vuelve a contar', () {
      final b = _Banco(esWeb: false);
      b.cambio(AppLifecycleState.paused);
      b.pasan(10);
      b.cambio(AppLifecycleState.resumed);
      b.cambio(AppLifecycleState.paused);
      b.pasan(5);
      b.cambio(AppLifecycleState.resumed);
      expect(b.salidas, 2);
      expect(b.volvio, [const Duration(seconds: 10), const Duration(seconds: 5)]);
    });
  });

  group('DetectorSalidas en web', () {
    test('inactive que dura más que la gracia cuenta y mide desde que quedó inactive', () {
      final b = _Banco(esWeb: true);
      b.cambio(AppLifecycleState.inactive);
      expect(b.salidas, 0);
      expect(b.timers, hasLength(1));
      b.pasan(2);
      b.timers.single.disparar();
      expect(b.salidas, 1);
      b.pasan(8);
      b.cambio(AppLifecycleState.resumed);
      expect(b.volvio, [const Duration(seconds: 10)]);
    });

    test('inactive corto seguido de resumed no cuenta', () {
      final b = _Banco(esWeb: true);
      b.cambio(AppLifecycleState.inactive);
      b.pasan(1);
      b.cambio(AppLifecycleState.resumed);
      expect(b.timers.single.cancelado, isTrue);
      b.timers.single.disparar();
      expect(b.salidas, 0);
      expect(b.volvio, isEmpty);
    });

    test('inactive repetido no crea otro timer', () {
      final b = _Banco(esWeb: true);
      b.cambio(AppLifecycleState.inactive);
      b.cambio(AppLifecycleState.inactive);
      expect(b.timers, hasLength(1));
    });

    test('inactive y después hidden cuenta una sola vez, desde que quedó inactive', () {
      final b = _Banco(esWeb: true);
      b.cambio(AppLifecycleState.inactive);
      b.pasan(1);
      b.cambio(AppLifecycleState.hidden);
      expect(b.salidas, 1);
      expect(b.timers.single.cancelado, isTrue);
      b.timers.single.disparar();
      expect(b.salidas, 1);
      b.pasan(4);
      b.cambio(AppLifecycleState.resumed);
      expect(b.volvio, [const Duration(seconds: 5)]);
    });

    test('hidden directo cuenta en el acto', () {
      final b = _Banco(esWeb: true);
      b.cambio(AppLifecycleState.hidden);
      expect(b.salidas, 1);
    });

    test('después de volver, una salida nueva vuelve a contar', () {
      final b = _Banco(esWeb: true);
      b.cambio(AppLifecycleState.inactive);
      b.pasan(3);
      b.timers.last.disparar();
      b.cambio(AppLifecycleState.resumed);
      b.cambio(AppLifecycleState.inactive);
      expect(b.timers, hasLength(2));
      b.pasan(3);
      b.timers.last.disparar();
      expect(b.salidas, 2);
    });

    test('dispose cancela el timer pendiente', () {
      final b = _Banco(esWeb: true);
      b.cambio(AppLifecycleState.inactive);
      b.detector.dispose();
      expect(b.timers.single.cancelado, isTrue);
    });
  });

  group('Cuestionario.estado', () {
    final c = Cuestionario.fromMap(_cuestionarioMap());
    test('sin publicar es borrador aunque esté en fecha', () {
      final sin = Cuestionario.fromMap(_cuestionarioMap(publicado: null));
      expect(sin.estado(DateTime.utc(2026, 11, 10, 11)), EstadoCuestionario.borrador);
    });
    test('antes de abrir está programado', () {
      expect(c.estado(DateTime.utc(2026, 11, 10, 9)), EstadoCuestionario.programado);
    });
    test('al abrir y antes de cerrar está abierto', () {
      expect(c.estado(DateTime.utc(2026, 11, 10, 10)), EstadoCuestionario.abierto);
      expect(c.estado(DateTime.utc(2026, 11, 10, 11, 59)), EstadoCuestionario.abierto);
    });
    test('en el instante de cierre y después está cerrado', () {
      expect(c.estado(DateTime.utc(2026, 11, 10, 12)), EstadoCuestionario.cerrado);
      expect(c.estado(DateTime.utc(2026, 11, 11)), EstadoCuestionario.cerrado);
    });
    test('fromMap lee los campos', () {
      expect(c.resultadosAlCerrar, isTrue);
      expect(c.duracionMin, 30);
      expect(c.topeSalidas, 3);
      expect(Cuestionario.fromMap(_cuestionarioMap(resultados: 'siempre')).resultadosAlCerrar, isFalse);
    });
  });

  group('Pregunta', () {
    test('fromMap de opción única lee opciones y correctas', () {
      final p = Pregunta.fromMap({
        'id': 'p1',
        'tipo': 'opcion',
        'enunciado': '¿2+2?',
        'opciones': ['3', '4'],
        'correctas': [1],
        'puntos': 2,
      });
      expect(p.tipo, TipoPregunta.opcion);
      expect(p.opciones, ['3', '4']);
      expect(p.correctas, [1]);
      expect(p.aceptadas, isEmpty);
      expect(p.puntos, 2);
    });

    test('fromMap de varias correctas', () {
      final p = Pregunta.fromMap({
        'tipo': 'varias',
        'enunciado': 'x',
        'opciones': ['a', 'b', 'c'],
        'correctas': [0, 2],
      });
      expect(p.correctas, [0, 2]);
      expect(p.puntos, 1);
    });

    test('fromMap de corta lee las aceptadas como texto', () {
      final p = Pregunta.fromMap({'tipo': 'corta', 'enunciado': 'x', 'correctas': ['Buenos Aires', 'BA']});
      expect(p.aceptadas, ['Buenos Aires', 'BA']);
      expect(p.correctas, isEmpty);
      expect(p.opciones, isEmpty);
    });

    test('fromMap sin correctas (lo ve el alumno) las deja vacías', () {
      final p = Pregunta.fromMap({'tipo': 'opcion', 'enunciado': 'x', 'opciones': ['a']});
      expect(p.correctas, isEmpty);
    });

    test('un tipo desconocido se toma como desarrollo', () {
      expect(Pregunta.fromMap({'tipo': 'raro', 'enunciado': 'x'}).tipo, TipoPregunta.desarrollo);
    });

    test('toMap por tipo', () {
      expect(
        const Pregunta(tipo: TipoPregunta.opcion, enunciado: 'e', opciones: ['a', 'b'], correctas: [1], puntos: 3).toMap(),
        {'tipo': 'opcion', 'enunciado': 'e', 'opciones': ['a', 'b'], 'correctas': [1], 'puntos': 3},
      );
      expect(
        const Pregunta(tipo: TipoPregunta.corta, enunciado: 'e', opciones: ['sobra'], aceptadas: ['si']).toMap(),
        {'tipo': 'corta', 'enunciado': 'e', 'opciones': <String>[], 'correctas': ['si'], 'puntos': 1},
      );
      final d = const Pregunta(tipo: TipoPregunta.desarrollo, enunciado: 'e', correctas: [1]).toMap();
      expect(d['correctas'], isNull);
      expect(d['opciones'], isEmpty);
    });

    test('conOpciones y automatica', () {
      expect(TipoPregunta.varias.conOpciones, isTrue);
      expect(TipoPregunta.corta.conOpciones, isFalse);
      expect(TipoPregunta.corta.automatica, isTrue);
      expect(TipoPregunta.desarrollo.automatica, isFalse);
    });
  });

  group('IntentoAbierto.fromMap', () {
    final m = {
      'ahora': '2026-11-10T10:00:10Z',
      'cuestionario': _cuestionarioMap(),
      'intento': _intentoMap(entregado: null),
      'preguntas': [
        {'id': 'p1', 'tipo': 'opcion', 'enunciado': 'x', 'opciones': ['a', 'b']},
        {'id': 'p2', 'tipo': 'desarrollo', 'enunciado': 'y'},
      ],
      'respuestas': {
        'p1': [1],
        'p2': 'texto libre',
        'p3': null,
      },
    };

    test('calcula el desfase contra la hora local', () {
      final a = IntentoAbierto.fromMap(m, ahoraLocal: DateTime.utc(2026, 11, 10, 10));
      expect(a.desfase, const Duration(seconds: 10));
      final b = IntentoAbierto.fromMap(m, ahoraLocal: DateTime.utc(2026, 11, 10, 10, 0, 20));
      expect(b.desfase, const Duration(seconds: -10));
    });

    test('lee respuestas como List<int> o String y descarta las nulas', () {
      final a = IntentoAbierto.fromMap(m, ahoraLocal: DateTime.utc(2026, 11, 10, 10));
      expect(a.respuestas['p1'], isA<List<int>>());
      expect(a.respuestas['p1'], [1]);
      expect(a.respuestas['p2'], 'texto libre');
      expect(a.respuestas.containsKey('p3'), isFalse);
      expect(a.preguntas, hasLength(2));
      expect(a.intento.entregado, isFalse);
    });
  });

  group('DetalleIntento.fromMap', () {
    test('lee preguntas sin correctas, valores, puntajes y eventos', () {
      final d = DetalleIntento.fromMap({
        'cuestionario': _cuestionarioMap(),
        'intento': _intentoMap(nota: 7.5),
        'alumno': 'Ana',
        'grupo': 'G1',
        'preguntas': [
          {'id': 'p1', 'tipo': 'opcion', 'enunciado': 'x', 'opciones': ['a', 'b'], 'valor': [0], 'puntaje': 1},
          {'id': 'p2', 'tipo': 'desarrollo', 'enunciado': 'y', 'valor': 'algo', 'puntaje': null, 'comentario': 'bien'},
          {'id': 'p3', 'tipo': 'corta', 'enunciado': 'z', 'valor': null},
        ],
        'eventos': [
          {'tipo': 'empezo', 'at': '2026-11-10T10:00:00Z'},
        ],
      });
      expect(d.alumno, 'Ana');
      expect(d.grupo, 'G1');
      expect(d.preguntas[0].pregunta.correctas, isEmpty);
      expect(d.preguntas[0].valor, [0]);
      expect(d.preguntas[0].puntaje, 1);
      expect(d.preguntas[0].respondida, isTrue);
      expect(d.preguntas[0].porCorregir, isFalse);
      expect(d.preguntas[1].porCorregir, isTrue);
      expect(d.preguntas[1].comentario, 'bien');
      expect(d.preguntas[2].respondida, isFalse);
      expect(d.eventos.single.texto, 'Empezó');
      expect(d.intento.nota, 7.5);
    });
  });

  group('ResultadoAlumno', () {
    test('principal es el entregado de mejor nota', () {
      final r = ResultadoAlumno(
        userId: 'u',
        nombre: 'Ana',
        intentos: [_intento(1, nota: 5), _intento(2, nota: 9), _intento(3, entregado: false)],
      );
      expect(r.principal!.numero, 2);
    });

    test('un entregado sin nota pierde contra uno con nota', () {
      final r = ResultadoAlumno(
        userId: 'u',
        nombre: 'Ana',
        intentos: [_intento(1), _intento(2, nota: 0)],
      );
      expect(r.principal!.numero, 2);
    });

    test('sin entregados devuelve el último intento', () {
      final r = ResultadoAlumno(
        userId: 'u',
        nombre: 'Ana',
        intentos: [_intento(1, entregado: false), _intento(2, entregado: false)],
      );
      expect(r.principal!.numero, 2);
    });

    test('sin intentos no hay principal', () {
      expect(const ResultadoAlumno(userId: 'u', nombre: 'Ana', intentos: []).principal, isNull);
    });

    test('suma salidas y segundos afuera de todos los intentos', () {
      final r = ResultadoAlumno(
        userId: 'u',
        nombre: 'Ana',
        intentos: [_intento(1, salidas: 2, afuera: 30), _intento(2, salidas: 1, afuera: 40)],
      );
      expect(r.salidas, 3);
      expect(r.segundosAfuera, 70);
    });

    test('fromMap usa "Alguien" si falta el nombre', () {
      final r = ResultadoAlumno.fromMap({'user_id': 'u', 'intentos': []});
      expect(r.nombre, 'Alguien');
    });
  });

  group('formatos', () {
    test('formatearSegundos', () {
      expect(formatearSegundos(0), '0 s');
      expect(formatearSegundos(45), '45 s');
      expect(formatearSegundos(60), '1 min');
      expect(formatearSegundos(65), '1 min 5 s');
      expect(formatearSegundos(180), '3 min');
      expect(formatearSegundos(3600), '1 h');
      expect(formatearSegundos(3900), '1 h 5 min');
    });

    test('textoReloj', () {
      expect(textoReloj(const Duration(minutes: 12, seconds: 5)), '12:05');
      expect(textoReloj(const Duration(hours: 1, minutes: 2, seconds: 5)), '1:02:05');
      expect(textoReloj(const Duration(seconds: 9)), '00:09');
      expect(textoReloj(const Duration(seconds: -5)), '00:00');
    });

    test('textoSalidas', () {
      expect(textoSalidas(1), '1 salida');
      expect(textoSalidas(3), '3 salidas');
      expect(textoSalidas(0), '0 salidas');
    });
  });

  group('mezclarCon', () {
    final base = List.generate(20, (i) => i);

    test('es determinístico para la misma semilla', () {
      expect(mezclarCon(base, 'intento-1'), mezclarCon(base, 'intento-1'));
    });

    test('es una permutación y no modifica la lista original', () {
      final r = mezclarCon(base, 'abc');
      expect([...r]..sort(), base);
      expect(base, List.generate(20, (i) => i));
    });

    test('semillas distintas dan órdenes distintos', () {
      expect(mezclarCon(base, 'a'), isNot(mezclarCon(base, 'b')));
    });

    test('lista vacía o de uno', () {
      expect(mezclarCon(<int>[], 'x'), isEmpty);
      expect(mezclarCon([1], 'x'), [1]);
    });
  });

  group('EventoIntento.texto', () {
    EventoIntento e(String tipo, {int? segundos, String? detalle}) =>
        EventoIntento(tipo: tipo, segundos: segundos, detalle: detalle, at: DateTime.utc(2026, 11, 10));

    test('textos por tipo', () {
      expect(e('empezo').texto, 'Empezó');
      expect(e('salio').texto, 'Salió de la pantalla');
      expect(e('volvio').texto, 'Volvió');
      expect(e('volvio', segundos: 65).texto, 'Volvió (estuvo 1 min 5 s afuera)');
      expect(e('reabrio').texto, 'Lo volvió a abrir (recargó, cerró la app u otra pestaña)');
      expect(e('reabrio', segundos: 120).texto, 'Lo volvió a abrir después de 2 min');
      expect(e('entrego').texto, 'Entregó');
      expect(e('entrego', detalle: 'tiempo').texto, 'Se entregó solo: se terminó el tiempo');
      expect(e('entrego', detalle: 'salidas').texto, 'Se entregó solo: salió más veces de las permitidas');
      expect(e('otro').texto, 'otro');
    });

    test('esSalida', () {
      expect(e('salio').esSalida, isTrue);
      expect(e('reabrio').esSalida, isTrue);
      expect(e('volvio').esSalida, isFalse);
    });
  });

  group('exportar resultados', () {
    final c = Cuestionario.fromMap(_cuestionarioMap());

    test('empieza con BOM, separa con ; y termina cada fila con CRLF', () {
      final csv = planillaDeResultados(c, [
        ResultadoAlumno(userId: 'u', nombre: 'Ana', grupo: 'G1', intentos: [_intento(1, nota: 7.5, salidas: 2, afuera: 65)]),
      ]);
      expect(csv.startsWith('﻿Alumno;Grupo;Intento;Estado;Nota;'), isTrue);
      expect(csv.endsWith('\r\n'), isTrue);
      final filas = csv.trimRight().split('\r\n');
      expect(filas, hasLength(2));
      final f = filas[1].split(';');
      expect(f.sublist(0, 9), ['Ana', 'G1', '1', 'Entregado', '7,5', '', '', '2', '1 min 5 s']);
      expect(f, hasLength(11));
    });

    test('alumno sin intentos sale como "No lo hizo"', () {
      final csv = planillaDeResultados(c, [const ResultadoAlumno(userId: 'u', nombre: 'Beto', intentos: [])]);
      expect(csv.trimRight().split('\r\n')[1], 'Beto;;;No lo hizo;;;;;;;');
    });

    test('un intento por corregir no muestra nota', () {
      final i = Intento.fromMap({..._intentoMap(nota: 6), 'pendiente': true});
      final csv = planillaDeResultados(c, [ResultadoAlumno(userId: 'u', nombre: 'Ana', intentos: [i])]);
      final f = csv.trimRight().split('\r\n')[1].split(';');
      expect(f[3], 'Por corregir');
      expect(f[4], '');
    });

    test('una fila por intento', () {
      final csv = planillaDeResultados(c, [
        ResultadoAlumno(userId: 'u', nombre: 'Ana', intentos: [_intento(1, nota: 5), _intento(2, nota: 8)]),
      ]);
      expect(csv.trimRight().split('\r\n'), hasLength(3));
    });

    test('escapa ;, comillas y saltos de línea', () {
      final csv = planillaDeResultados(c, [
        const ResultadoAlumno(userId: 'u', nombre: 'Pérez; "Juan"', grupo: 'a\nb', intentos: []),
      ]);
      expect(csv, contains('"Pérez; ""Juan"""'));
      expect(csv, contains('"a\nb"'));
    });

    test('nombreResultados saca los caracteres inválidos', () {
      expect(nombreResultados('Parcial 1'), 'Resultados - Parcial 1.csv');
      expect(nombreResultados(r'a/b\c:d*e?f"g<h>i|j'), 'Resultados - a-b-c-d-e-f-g-h-i-j.csv');
    });
  });
}
