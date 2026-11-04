import 'package:flutter_test/flutter_test.dart';
import 'package:tpdrive/features/groups/data/supabase_groups_repository.dart';
import 'package:tpdrive/features/groups/domain/group.dart';
import 'package:tpdrive/features/groups/domain/invite.dart';

Map<String, dynamic> _perfil(String id, String nombre) => {
      'id': id,
      'nombre': nombre,
      'avatar_url': null,
      'plan': 'free',
      'created_at': '2026-11-01T12:00:00Z',
    };

void main() {
  group('Invite', () {
    test('normaliza y formatea', () {
      expect(Invite.normalizar(' abcd-2345 '), 'ABCD2345');
      expect(Invite.formatear('abcd2345'), 'ABCD-2345');
      expect(Invite.formatear('abcde23456'), 'ABCDE-23456');
    });

    test('valida el alfabeto sin caracteres ambiguos', () {
      expect(Invite.esCodigoValido('ABCD2345'), isTrue);
      expect(Invite.esCodigoValido('ABCD-2345'), isTrue);
      expect(Invite.esCodigoValido('ABCDE-23456'), isTrue, reason: 'los nuevos tienen 10');
      expect(Invite.esCodigoValido('ABCDE2345'), isFalse, reason: '9 no es un largo válido');
      expect(Invite.esCodigoValido('ABCD234'), isFalse, reason: 'muy corto');
      expect(Invite.esCodigoValido('ABCD0345'), isFalse, reason: 'el 0 no se usa');
      expect(Invite.esCodigoValido('OBCD2345'), isFalse, reason: 'la O no se usa');
    });

    test('arma el link de invitación', () {
      expect(Invite.link('https://tpdrive.app/', 'abcd-2345'),
          'https://tpdrive.app/#/unirse/ABCD2345');
    });

    test('extrae el código de un link o de un código suelto', () {
      expect(Invite.extraerCodigo('http://localhost:3000/#/unirse/ABCD2345'), 'ABCD2345');
      expect(Invite.extraerCodigo('abcd-2345'), 'ABCD2345');
      expect(Invite.extraerCodigo('http://localhost:3000/#/unirse/ABCDE23456'), 'ABCDE23456');
      expect(Invite.extraerCodigo('hola'), isNull);
    });
  });

  group('Group', () {
    test('fromMap con rol y cantidad de integrantes', () {
      final g = Group.fromMap({
        'id': 'g1',
        'nombre': 'TP Física',
        'materia': null,
        'invite_code': 'ABCD2345',
        'plan': 'free',
        'storage_used': 1024,
        'created_by': 'u1',
        'created_at': '2026-11-01T12:00:00Z',
      }, miRol: GroupRole.admin, cantidadMiembros: 3);
      expect(g.soyAdmin, isTrue);
      expect(g.storageUsed, 1024);
      expect(g.cantidadMiembros, 3);
    });

    test('ordena integrantes: admins primero, después por nombre', () {
      GroupMember m(String nombre, String rol) => GroupMember.fromMap({
            'rol': rol,
            'joined_at': '2026-11-01T12:00:00Z',
            'profiles': _perfil(nombre, nombre),
          });
      final orden = ordenarMiembros([m('beto', 'miembro'), m('Zoe', 'admin'), m('Ana', 'miembro')]);
      expect(orden.map((e) => e.profile.nombre), ['Zoe', 'Ana', 'beto']);
    });
  });

  test('errores de grupos en español', () {
    expect(traducirErrorGrupo('P0002', 'x'), contains('código de invitación'));
    expect(traducirErrorGrupo('P0001', 'Nombrá a otro admin antes de salir del grupo'),
        'Nombrá a otro admin antes de salir del grupo');
    expect(traducirErrorGrupo('42501', 'x'), 'No tenés permiso para hacer esto');
  });
}
