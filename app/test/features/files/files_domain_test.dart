import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tpdrive/features/files/data/supabase_files_repository.dart';
import 'package:tpdrive/features/files/domain/file_item.dart';
import 'package:tpdrive/features/files/domain/files_repository.dart';
import 'package:tpdrive/features/files/domain/folder_tree.dart';
import 'package:tpdrive/features/files/presentation/uploads_controller.dart';

Folder _carpeta(String id, String? padre, String nombre) => Folder(
      id: id,
      groupId: 'g',
      parentId: padre,
      nombre: nombre,
      createdAt: DateTime.utc(2026),
    );

FileItem _archivo(String nombre, {String? lockedBy, DateTime? lockedAt}) => FileItem(
      id: nombre,
      groupId: 'g',
      nombre: nombre,
      lockedBy: lockedBy,
      lockedAt: lockedAt,
      createdAt: DateTime.utc(2026),
    );

void main() {
  group('tipo de archivo por extensión', () {
    test('reconoce los tipos comunes', () {
      expect(fileKindFor('Informe final.DOCX'), FileKind.documento);
      expect(fileKindFor('datos.xlsx'), FileKind.planilla);
      expect(fileKindFor('consigna.pdf'), FileKind.pdf);
      expect(fileKindFor('foto.JPEG'), FileKind.imagen);
      expect(fileKindFor('main.py'), FileKind.codigo);
    });

    test('sin extensión o desconocida es "otro"', () {
      expect(fileKindFor('Makefile'), FileKind.otro);
      expect(fileKindFor('.gitignore'), FileKind.otro);
      expect(fileKindFor('raro.xyz'), FileKind.otro);
      expect(fileKindFor('termina.'), FileKind.otro);
    });
  });

  test('formatBytes', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1024), '1 KB');
    expect(formatBytes(1536), '1,5 KB');
    expect(formatBytes(5 * 1024 * 1024), '5 MB');
    expect(formatBytes(250 * 1024 * 1024), '250 MB');
  });

  group('formatearFecha', () {
    final ahora = DateTime(2026, 11, 1, 15, 0);
    test('relativa si es reciente', () {
      expect(formatearFecha(ahora.subtract(const Duration(seconds: 20)), ahora), 'recién');
      expect(formatearFecha(ahora.subtract(const Duration(minutes: 5)), ahora), 'hace 5 min');
      expect(formatearFecha(DateTime(2026, 11, 1, 9, 0), ahora), 'hace 6 h');
    });
    test('ayer y fechas', () {
      expect(formatearFecha(DateTime(2026, 10, 31, 23, 0), ahora), 'ayer');
      expect(formatearFecha(DateTime(2026, 3, 12), ahora), '12 mar');
      expect(formatearFecha(DateTime(2025, 3, 12), ahora), '12 mar 2025');
    });
  });

  group('carpetas', () {
    final carpetas = [
      _carpeta('a', null, 'Informe'),
      _carpeta('b', 'a', 'Anexos'),
      _carpeta('c', 'b', 'Imágenes'),
      _carpeta('d', null, 'Código'),
    ];

    test('ruta para los breadcrumbs', () {
      expect(rutaHasta('c', carpetas).map((c) => c.nombre), ['Informe', 'Anexos', 'Imágenes']);
      expect(rutaHasta(null, carpetas), isEmpty);
      expect(rutaHasta('no-existe', carpetas), isEmpty);
    });

    test('no se cuelga con un ciclo', () {
      final ciclo = [_carpeta('x', 'y', 'X'), _carpeta('y', 'x', 'Y')];
      expect(rutaHasta('x', ciclo).length, 2);
    });

    test('subcarpetas ordenadas', () {
      expect(hijasDe(null, carpetas).map((c) => c.nombre), ['Código', 'Informe']);
      expect(hijasDe('a', carpetas).map((c) => c.nombre), ['Anexos']);
    });
  });

  test('mismo nombre sin distinguir mayúsculas = versión nueva', () {
    final archivos = [_archivo('Informe.docx')];
    expect(archivoConNombre(' informe.DOCX ', archivos)?.nombre, 'Informe.docx');
    expect(archivoConNombre('Informe v2.docx', archivos), isNull);
  });

  test('los bloqueos vencen a las 24 h', () {
    final ahora = DateTime(2026, 11, 1, 12);
    expect(_archivo('a', lockedBy: 'u', lockedAt: ahora.subtract(const Duration(hours: 23)))
        .estaBloqueado(ahora), isTrue);
    expect(_archivo('a', lockedBy: 'u', lockedAt: ahora.subtract(const Duration(hours: 25)))
        .estaBloqueado(ahora), isFalse);
    expect(_archivo('a').estaBloqueado(ahora), isFalse);
  });

  group('estado del bloqueo', () {
    final ahora = DateTime(2026, 11, 1, 12);
    final deBeto = _archivo('a', lockedBy: 'beto', lockedAt: ahora.subtract(const Duration(hours: 2)));

    test('libre, mío o de otro', () {
      expect(_archivo('a').estadoBloqueo('ana', ahora), EstadoBloqueo.libre);
      expect(deBeto.estadoBloqueo('beto', ahora), EstadoBloqueo.mio);
      expect(deBeto.estadoBloqueo('ana', ahora), EstadoBloqueo.deOtro);
    });

    test('vencido cuenta como libre', () {
      final viejo = _archivo('a', lockedBy: 'beto', lockedAt: ahora.subtract(const Duration(hours: 25)));
      expect(viejo.estadoBloqueo('ana', ahora), EstadoBloqueo.libre);
      expect(viejo.vencimientoBloqueo(ahora), isNull);
    });

    test('cuánto falta para que se libere', () {
      expect(deBeto.vencimientoBloqueo(ahora), const Duration(hours: 22));
      expect(formatearVencimiento(const Duration(hours: 22)), 'se libera en 22 h');
      expect(formatearVencimiento(const Duration(minutes: 40)), 'se libera en 40 min');
      expect(formatearVencimiento(const Duration(seconds: 10)), 'se libera en 1 min');
    });
  });

  group('qué se puede subir', () {
    Subida subida({int tamano = 100, String? copiaPorque}) => Subida(
          nombre: 'x.pdf',
          tamano: tamano,
          leer: () async => Uint8List(0),
          copiaPorque: copiaPorque,
        );

    test('se puede subir', () => expect(subida().impedimento, isNull));
    test('aunque lo edite otra persona (va como copia)', () {
      expect(subida(copiaPorque: 'Juan').impedimento, isNull);
    });
    test('no si supera el máximo', () {
      expect(subida(tamano: maxBytesPorArchivo + 1).impedimento, contains('50 MB'));
    });
  });

  group('bloqueos flexibles', () {
    final ahora = DateTime(2026, 11, 1, 12);

    test('vence en lock_until', () {
      final f = FileItem(
        id: 'f',
        groupId: 'g',
        nombre: 'a.docx',
        lockedBy: 'beto',
        lockedAt: ahora.subtract(const Duration(minutes: 30)),
        lockUntil: ahora.add(const Duration(minutes: 90)),
        createdAt: DateTime.utc(2026),
      );
      expect(f.vencimientoBloqueo(ahora), const Duration(minutes: 90));
      expect(f.estaBloqueado(ahora.add(const Duration(hours: 2))), isFalse);
    });

    test('duración elegida', () {
      expect(minutosDeBloqueo(DuracionBloqueo.dosHoras, ahora), 120);
      expect(minutosDeBloqueo(DuracionBloqueo.unDia, ahora), 1440);
      expect(minutosDeBloqueo(DuracionBloqueo.hastaLaNoche, ahora), 11 * 60 + 59);
      expect(minutosDeBloqueo(DuracionBloqueo.hastaLaNoche, DateTime(2026, 11, 1, 23)), 120,
          reason: 'si ya es tarde, al menos 2 h');
    });

    test('nombre de la copia', () {
      final existentes = [_archivo('Informe.docx'), _archivo('Informe (copia de Ana).docx')];
      expect(nombreCopia('Informe.docx', 'Juan', existentes), 'Informe (copia de Juan).docx');
      expect(nombreCopia('Informe.docx', 'Ana', existentes), 'Informe (copia de Ana 2).docx');
      expect(nombreCopia('Makefile', 'Ana', existentes), 'Makefile (copia de Ana)');
    });

    test('pedidos desde la base', () {
      final f = FileItem.fromMap({
        'id': 'f',
        'group_id': 'g',
        'nombre': 'a.docx',
        'locked_by': 'beto',
        'locked_at': '2026-11-01T12:00:00Z',
        'lock_until': '2026-11-01T14:00:00Z',
        'pedidos': [
          {'requested_by': 'ana', 'created_at': '2026-11-01T12:30:00Z', 'requester': {'nombre': 'Ana'}},
        ],
        'created_at': '2026-11-01T10:00:00Z',
      });
      expect(f.pedidoPor('ana'), isTrue);
      expect(f.pedidoPor('caro'), isFalse);
      expect(f.pedidos.single.nombre, 'Ana');
    });
  });

  test('errores en español', () {
    expect(traducirErrorArchivos('P0001', 'La carpeta no está vacía'), 'La carpeta no está vacía');
    expect(traducirErrorArchivos('42501', 'new row violates row-level security policy'),
        'No tenés permiso para hacer esto');
    expect(traducirErrorArchivos('23505', 'duplicate key'), 'Ya hay una carpeta con ese nombre acá');
    expect(traducirErrorStorage('413', 'Payload too large'), contains('tamaño máximo'));
  });

  test('versión desde la fila de la base', () {
    final v = FileVersion.fromMap({
      'id': 'v1',
      'file_id': 'f1',
      'version_number': 3,
      'storage_path': 'groups/g/files/f1/v3',
      'size_bytes': 2048,
      'mime_type': 'application/pdf',
      'nota': 'corregí la conclusión',
      'uploaded_by': 'u1',
      'uploader': {'nombre': 'Juan'},
      'created_at': '2026-11-01T12:00:00Z',
    });
    expect(v.versionNumber, 3);
    expect(v.uploaderNombre, 'Juan');
  });
}
