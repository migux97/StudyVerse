import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode.dart';
import 'core/widgets/avisos.dart';
import 'features/files/domain/file_item.dart';
import 'features/files/domain/files_repository.dart';
import 'features/files/presentation/files_providers.dart';

/// Para mostrar avisos que no dependen de la pantalla actual.
class StudyVerseApp extends ConsumerWidget {
  const StudyVerseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // "Ana necesita editar Informe.docx": llega aunque estés en otra pantalla.
    ref.listen(pedidosEntrantesProvider, (_, pedido) {
      if (pedido case AsyncData(:final value)) _avisarPedido(ref, value);
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
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
    );
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
