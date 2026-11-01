import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/env.dart';
import '../../../core/widgets/auth_layout.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../domain/group.dart';
import '../domain/invite.dart';
import '../domain/telegram.dart';
import 'group_shell.dart';
import 'groups_providers.dart';

/// "Conectar Telegram": el admin genera un código y en el grupo de Telegram
/// se manda /vincular CODIGO. Muestra los chats conectados.
class TelegramScreen extends StatelessWidget {
  const TelegramScreen({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context) => GroupLoader(
        groupId: groupId,
        builder: (g) => Scaffold(
          appBar: AppBar(title: const Text('Avisos por Telegram')),
          body: _Telegram(grupo: g),
        ),
      );
}

class _Telegram extends ConsumerStatefulWidget {
  const _Telegram({required this.grupo});
  final Group grupo;

  @override
  ConsumerState<_Telegram> createState() => _TelegramState();
}

class _TelegramState extends ConsumerState<_Telegram> {
  CodigoTelegram? _codigo;
  bool _generando = false;

  Group get grupo => widget.grupo;

  Future<void> _generar() async {
    setState(() => _generando = true);
    try {
      final c = await ref.read(telegramRepositoryProvider).crearCodigo(grupo.id);
      if (mounted) setState(() => _codigo = c);
    } on TelegramFailure catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  Future<void> _desvincular(TelegramLink l) async {
    final ok = await confirmar(
      context,
      titulo: '¿Desconectar "${l.chatTitle ?? 'el chat'}"?',
      mensaje: 'Ese chat deja de recibir los avisos del grupo.',
      accion: 'Desconectar',
      peligroso: true,
    );
    if (!ok) return;
    try {
      await ref.read(telegramRepositoryProvider).desvincular(grupo.id, l.chatId);
      ref.invalidate(telegramLinksProvider(grupo.id));
    } on TelegramFailure catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final links = ref.watch(telegramLinksProvider(grupo.id));
    final lista = links.value ?? const <TelegramLink>[];

    // Si se conectó un chat con el código en pantalla, ya no hace falta mostrarlo.
    ref.listen(telegramLinksProvider(grupo.id), (antes, ahora) {
      final n = ahora.value?.length ?? 0;
      if (_codigo != null && n > (antes?.value?.length ?? 0)) {
        setState(() => _codigo = null);
        mostrarMensaje(context, '¡Listo! Telegram quedó conectado');
      }
    });

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'El bot avisa en un grupo de Telegram cuando alguien sube una versión nueva, '
              'empieza o termina de editar un archivo o completa una tarea, y recuerda '
              'las fechas límite el día anterior.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Text('Chats conectados', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Card(
              child: links.isLoading && !links.hasValue
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : lista.isEmpty
                      ? const ListTile(
                          leading: Icon(Icons.notifications_off_outlined),
                          title: Text('Todavía no hay ningún chat conectado'),
                        )
                      : Column(children: [
                          for (final l in lista)
                            ListTile(
                              leading: const Icon(Icons.forum_outlined),
                              title: Text(l.chatTitle ?? 'Chat de Telegram'),
                              subtitle: const Text('Recibe los avisos del grupo'),
                              trailing: grupo.soyAdmin
                                  ? TextButton(onPressed: () => _desvincular(l), child: const Text('Desconectar'))
                                  : null,
                            ),
                        ]),
            ),
            const SizedBox(height: 24),
            if (!grupo.soyAdmin)
              Text(
                'Solo el admin del grupo puede conectar Telegram.',
                style: theme.textTheme.bodyMedium,
              )
            else if (_codigo == null)
              FilledButton.icon(
                icon: const Icon(Icons.add_link),
                label: Text(lista.isEmpty ? 'Conectar un grupo de Telegram' : 'Conectar otro chat'),
                onPressed: _generando ? null : _generar,
              )
            else
              _Pasos(codigo: _codigo!, onNuevo: _generar),
          ],
        ),
      ),
    );
  }
}

class _Pasos extends StatelessWidget {
  const _Pasos({required this.codigo, required this.onNuevo});
  final CodigoTelegram codigo;
  final VoidCallback onNuevo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final comando = '/vincular ${Invite.formatear(codigo.codigo)}';
    final bot = Env.telegramBot;
    final vence = TimeOfDay.fromDateTime(codigo.vence.toLocal()).format(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Conectar en 2 pasos', style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          Text('1. Agregá ${bot.isEmpty ? 'el bot de TP Drive' : '@$bot'} al grupo de Telegram del TP.'),
          if (bot.isNotEmpty) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: Text('Abrir @$bot en Telegram'),
              onPressed: () => launchUrl(Uri.parse(linkAgregarBot(bot)), mode: LaunchMode.externalApplication),
            ),
          ],
          const SizedBox(height: 16),
          const Text('2. Mandá este mensaje en ese grupo:'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Expanded(
                child: SelectableText(
                  comando,
                  style: theme.textTheme.titleMedium?.copyWith(fontFamily: 'monospace'),
                ),
              ),
              IconButton(
                tooltip: 'Copiar',
                icon: const Icon(Icons.copy_rounded),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: comando));
                  if (context.mounted) mostrarMensaje(context, 'Copiado');
                },
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Text(
                'El código sirve una sola vez y vence a las $vence. '
                'Esta pantalla se actualiza sola cuando se conecta.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            TextButton(onPressed: onNuevo, child: const Text('Otro código')),
          ]),
        ]),
      ),
    );
  }
}
