import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/files/domain/file_item.dart';
import 'features/files/domain/files_repository.dart';
import 'features/files/presentation/files_providers.dart';

/// Para mostrar avisos que no dependen de la pantalla actual.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class TpDriveApp extends ConsumerWidget {
  const TpDriveApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // "Ana necesita editar Informe.docx": llega aunque estés en otra pantalla.
    ref.listen(pedidosEntrantesProvider, (_, pedido) {
      if (pedido case AsyncData(:final value)) _avisarPedido(ref, value);
    });

    return MaterialApp.router(
      title: 'TP Drive',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      locale: const Locale('es', 'AR'),
      supportedLocales: const [Locale('es', 'AR'), Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }

  void _avisarPedido(WidgetRef ref, PedidoEntrante p) {
    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 20),
        showCloseIcon: true,
        content: Text('${p.quien} necesita editar "${p.archivo}". ¿Lo liberás?'),
        action: SnackBarAction(
          label: 'Liberar',
          onPressed: () async {
            try {
              await ref.read(filesRepositoryProvider).unlock(p.fileId);
              ref.invalidate(filesProvider((groupId: p.groupId, folderId: p.folderId)));
              messenger.showSnackBar(SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text('Listo, ${p.quien} ya puede editarlo'),
              ));
            } on FilesFailure catch (e) {
              messenger.showSnackBar(SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text(e.mensaje),
              ));
            }
          },
        ),
      ));
  }
}
