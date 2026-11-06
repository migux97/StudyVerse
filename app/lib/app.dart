import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'features/comentarios/domain/comentario.dart';
import 'features/comentarios/presentation/comentarios_providers.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode.dart';
import 'core/widgets/avisos.dart';
import 'features/files/domain/file_item.dart';
import 'features/files/domain/files_repository.dart';
import 'features/files/presentation/files_providers.dart';
import 'features/tasks/domain/task.dart';
import 'features/tasks/presentation/tasks_providers.dart';
import 'features/avisos/domain/aviso.dart';
import 'features/avisos/presentation/avisos_providers.dart';
import 'features/groups/presentation/groups_providers.dart';
import 'core/push/push.dart';
import 'features/auth/presentation/auth_providers.dart';

/// Para mostrar avisos que no dependen de la pantalla actual.
class StudyVerseApp extends ConsumerStatefulWidget {
  const StudyVerseApp({super.key});

  @override
  ConsumerState<StudyVerseApp> createState() => _StudyVerseAppState();
}

class _StudyVerseAppState extends ConsumerState<StudyVerseApp> {
  StreamSubscription<String>? _tocadas;
  String? _rutaPendiente;
  static const _pushPedido = 'push_permiso_pedido';

  @override
  void initState() {
    super.initState();
    // Tocar un push (con la app cerrada o de fondo) abre esa pantalla.
    // Si todavía no hay sesión, se abre después de entrar.
    _tocadas = ref.read(pushProvider).rutasTocadas.listen((ruta) {
      if (ref.read(authStateProvider).value == null) {
        _rutaPendiente = ruta;
      } else {
        ref.read(routerProvider).push(ruta);
      }
    });
    // Al entrar: si este dispositivo ya dio permiso, queda registrado. En
    // Android se pide la primera vez; en la web, desde la campanita (el
    // navegador exige un toque).
    ref.listenManual(authStateProvider.select((s) => s.value?.id), (_, id) {
      if (id == null) return;
      if (_rutaPendiente case final ruta?) {
        _rutaPendiente = null;
        WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(routerProvider).push(ruta));
      }
      final prefs = ref.read(sharedPreferencesProvider);
      ref.read(pushProvider).alEntrar(
        yaSePidio: prefs?.getBool(_pushPedido) ?? false,
        marcarPedido: () async => prefs?.setBool(_pushPedido, true),
      ).catchError((_) {});
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _tocadas?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    // "Ana necesita editar Informe.docx": llega aunque estés en otra pantalla.
    ref.listen(pedidosEntrantesProvider, (_, pedido) {
      if (pedido case AsyncData(:final value)) _avisarPedido(ref, value);
    });
    ref.listen(mencionesProvider, (_, next) {
      if (next.value case final c?) _avisarMencion(ref, c);
    });
    ref.listen(revisionesProvider, (_, next) {
      if (next.value case final r?) _avisarRevision(ref, r);
    });
    ref.listen(avisosEntrantesProvider, (_, next) {
      if (next.value case final a?) _avisarDocente(ref, a);
    });

    return MaterialApp.router(
      title: 'StudyVerse',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      locale: const Locale('es', 'AR'),
      supportedLocales: const [Locale('es', 'AR'), Locale('es')],
      localizationsDelegates: const [...GlobalMaterialLocalizations.delegates, FlutterQuillLocalizations.delegate],
      routerConfig: ref.watch(routerProvider),
      // En la web de PC, las listas que se deslizan de costado también se
      // arrastran con el mouse.
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {...const MaterialScrollBehavior().dragDevices, PointerDeviceKind.mouse},
      ),
    );
  }

  void _avisarMencion(WidgetRef ref, Comentario c) {
    final ctx = scaffoldMessengerKey.currentContext;
    final messenger = scaffoldMessengerKey.currentState;
    if (ctx == null || messenger == null) return;
    final archivo = nombreVisible(c.archivo ?? 'un archivo');
    final destino = fileKindFor(c.archivo ?? '') == FileKind.studyverse
        ? Routes.documento(c.groupId, c.fileId)
        : Routes.archivo(c.groupId, c.fileId);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(aviso(
        ctx,
        '${c.autor?.nombre ?? 'Alguien'} te mencionó en «$archivo»',
        duracion: const Duration(seconds: 12),
        cerrable: true,
        accion: 'Ver',
        alTocar: () => ref.read(routerProvider).push(destino),
      ));
  }

  /// Aviso del docente o devolución de una tarea: llega en cualquier pantalla.
  void _avisarDocente(WidgetRef ref, AvisoEntrante a) {
    final ctx = scaffoldMessengerKey.currentContext;
    final messenger = scaffoldMessengerKey.currentState;
    if (ctx == null || messenger == null) return;
    final (texto, destino) = switch (a) {
      AvisoNuevo(:final aviso, :final groupId) => (
          a.mensaje,
          // A todo el curso: se abre mi grupo de ese curso.
          groupId ??
              ref.read(myGroupsProvider).value?.where((g) => g.cursoId == aviso.cursoId).firstOrNull?.id,
        ),
      DevolucionNueva(:final devolucion) => (a.mensaje, devolucion.groupId),
    };
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(aviso(
        ctx,
        texto.length > 140 ? '${texto.substring(0, 140)}…' : texto,
        duracion: const Duration(seconds: 12),
        cerrable: true,
        accion: 'Ver',
        // Si todavía no sé en cuál de mis grupos está, voy al inicio.
        alTocar: () => ref.read(routerProvider).push(switch (destino) {
          null => Routes.grupos,
          final id when a is DevolucionNueva => Routes.tareas(id),
          final id => Routes.grupo(id),
        }),
      ));
  }

  void _avisarRevision(WidgetRef ref, Revision r) {
    final ctx = scaffoldMessengerKey.currentContext;
    final messenger = scaffoldMessengerKey.currentState;
    if (ctx == null || messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(aviso(
        ctx,
        r.mensaje,
        duracion: const Duration(seconds: 12),
        cerrable: true,
        accion: 'Ver',
        alTocar: () => ref.read(routerProvider).push(Routes.tareas(r.groupId)),
      ));
  }

  void _avisarPedido(WidgetRef ref, PedidoEntrante p) {
    final messenger = scaffoldMessengerKey.currentState;
    final ctx = scaffoldMessengerKey.currentContext;
    if (messenger == null || ctx == null) return;
    // Los avisos de respuesta se arman antes del await (el contexto es el de la app).
    final listo = aviso(ctx, 'Listo, ${p.quien} ya puede editarlo');
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(aviso(
        ctx,
        '${p.quien} quiere editar «${p.archivo}»',
        duracion: const Duration(seconds: 20),
        cerrable: true,
        accion: 'Liberar',
        alTocar: () async {
          try {
            await ref.read(filesRepositoryProvider).unlock(p.fileId);
            ref.invalidate(filesProvider((groupId: p.groupId, folderId: p.folderId)));
            messenger.showSnackBar(listo);
          } on FilesFailure catch (e) {
            final c = scaffoldMessengerKey.currentContext;
            if (c != null && c.mounted) messenger.showSnackBar(aviso(c, e.mensaje));
          }
        },
      ));
  }
}
