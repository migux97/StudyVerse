import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/auth_layout.dart';
import '../../auth/domain/profile.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/presentation/user_avatar.dart';
import '../../files/domain/file_item.dart' show formatearFecha;
import '../../groups/presentation/groups_providers.dart';
import '../domain/comentario.dart';
import 'comentarios_providers.dart';

/// Botón de la barra con la cantidad de comentarios. En pantallas anchas abre
/// el panel al costado ([alAlternarPanel]); en el celular, una hoja desde abajo.
class BotonComentarios extends ConsumerWidget {
  const BotonComentarios({super.key, required this.groupId, required this.fileId, this.alAlternarPanel});
  final String groupId;
  final String fileId;
  final VoidCallback? alAlternarPanel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(comentariosProvider((groupId: groupId, fileId: fileId))).value?.length ?? 0;
    return IconButton(
      tooltip: 'Comentarios',
      icon: Badge(
        isLabelVisible: n > 0,
        label: Text('$n'),
        child: const Icon(Icons.chat_bubble_outline),
      ),
      onPressed: alAlternarPanel ??
          () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                showDragHandle: true,
                // El contexto de la hoja: así el alto del teclado se actualiza.
                builder: (hoja) => Padding(
                  padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(hoja).bottom),
                  child: SizedBox(
                    height: MediaQuery.sizeOf(hoja).height * 0.75,
                    child: ComentariosPanel(groupId: groupId, fileId: fileId),
                  ),
                ),
              ),
    );
  }
}

/// Comentarios de un archivo: la conversación y un campo para escribir, con
/// sugerencias al escribir @.
class ComentariosPanel extends ConsumerStatefulWidget {
  const ComentariosPanel({super.key, required this.groupId, required this.fileId, this.alCerrar});
  final String groupId;
  final String fileId;
  final VoidCallback? alCerrar;

  @override
  ConsumerState<ComentariosPanel> createState() => _ComentariosPanelState();
}

class _ComentariosPanelState extends ConsumerState<ComentariosPanel> {
  final _texto = TextEditingController();
  final _foco = FocusNode();
  final _scroll = ScrollController();
  bool _enviando = false;

  /// Integrantes que coinciden con la @ que se está escribiendo.
  List<Profile> _sugerencias = const [];

  @override
  void initState() {
    super.initState();
    _texto.addListener(_buscarMencion);
  }

  @override
  void dispose() {
    _texto.dispose();
    _foco.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _buscarMencion() {
    final enCurso = mencionEnCurso(_texto.text, _texto.selection.baseOffset);
    final miId = ref.read(authStateProvider).value?.id;
    final miembros = ref.read(groupMembersProvider(widget.groupId)).value ?? const [];
    final nuevas = enCurso == null
        ? const <Profile>[]
        : [
            for (final m in miembros)
              if (m.profile.id != miId &&
                  m.profile.username != null &&
                  (m.profile.username!.toLowerCase().startsWith(enCurso.buscado) ||
                      m.profile.nombre.toLowerCase().contains(enCurso.buscado)))
                m.profile,
          ].take(5).toList();
    final antes = {for (final p in _sugerencias) p.id};
    if (nuevas.length != antes.length || !nuevas.every((p) => antes.contains(p.id))) {
      setState(() => _sugerencias = nuevas);
    }
  }

  void _elegir(Profile p) {
    final enCurso = mencionEnCurso(_texto.text, _texto.selection.baseOffset);
    if (enCurso == null || p.username == null) return;
    final r = completarMencion(_texto.text, enCurso.inicio, _texto.selection.baseOffset, p.username!);
    _texto.value = TextEditingValue(text: r.texto, selection: TextSelection.collapsed(offset: r.cursor));
    _foco.requestFocus();
  }

  Future<void> _enviar() async {
    final texto = _texto.text.trim();
    if (texto.isEmpty || _enviando) return;
    if (texto.length > 2000) return mostrarMensaje(context, 'Es muy largo: usá hasta 2000 caracteres');
    setState(() => _enviando = true);
    try {
      await ref
          .read(comentariosRepositoryProvider)
          .comentar(fileId: widget.fileId, groupId: widget.groupId, texto: texto);
      // La hoja se pudo cerrar mientras se enviaba.
      if (!mounted) return;
      _texto.clear();
      ref.invalidate(comentariosProvider((groupId: widget.groupId, fileId: widget.fileId)));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });
    } on ComentarioFailure catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _borrar(Comentario c) async {
    try {
      await ref.read(comentariosRepositoryProvider).borrar(c.id);
      if (!mounted) return;
      ref.invalidate(comentariosProvider((groupId: widget.groupId, fileId: widget.fileId)));
    } on ComentarioFailure catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lista = ref.watch(comentariosProvider((groupId: widget.groupId, fileId: widget.fileId)));
    // Para tener los integrantes a mano cuando se escriba @.
    ref.watch(groupMembersProvider(widget.groupId));
    final miId = ref.watch(authStateProvider).value?.id;
    final ahora = DateTime.now();

    return Material(
      color: scheme.surfaceContainerLowest,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
          child: Row(children: [
            Expanded(child: Text('Comentarios', style: theme.textTheme.titleMedium)),
            if (widget.alCerrar != null)
              IconButton(tooltip: 'Cerrar comentarios', icon: const Icon(Icons.close), onPressed: widget.alCerrar),
          ]),
        ),
        Expanded(
          child: lista.when(
            skipLoadingOnReload: true,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: TextButton(
                onPressed: () => ref.invalidate(comentariosProvider((groupId: widget.groupId, fileId: widget.fileId))),
                child: const Text('No pudimos cargar los comentarios. Reintentar'),
              ),
            ),
            data: (cs) => cs.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Todavía no hay comentarios.\nEscribí uno y mencioná a alguien con @ para avisarle.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    itemCount: cs.length,
                    itemBuilder: (_, i) => _Burbuja(
                      comentario: cs[i],
                      cuando: formatearFecha(cs[i].createdAt, ahora),
                      mio: cs[i].autor?.id == miId,
                      alBorrar: () => _borrar(cs[i]),
                    ),
                  ),
          ),
        ),
        if (_sugerencias.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant))),
            child: ListView(shrinkWrap: true, children: [
              for (final p in _sugerencias)
                ListTile(
                  dense: true,
                  leading: UserAvatar(profile: p, radius: 14),
                  title: Text(p.nombre),
                  subtitle: Text('@${p.username}'),
                  onTap: () => _elegir(p),
                ),
            ]),
          ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: CallbackShortcuts(
                // En la PC, Enter envía y Shift+Enter hace un salto de línea.
                bindings: {const SingleActivator(LogicalKeyboardKey.enter): _enviar},
                child: TextField(
                  controller: _texto,
                  focusNode: _foco,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(hintText: 'Escribí un comentario… (@ para mencionar)', isDense: true),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Enviar',
              icon: _enviando
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded),
              onPressed: _enviando ? null : _enviar,
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Burbuja extends StatelessWidget {
  const _Burbuja({required this.comentario, required this.cuando, required this.mio, required this.alBorrar});
  final Comentario comentario;
  final String cuando;
  final bool mio;
  final VoidCallback alBorrar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = comentario;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (c.autor != null) UserAvatar(profile: c.autor!, radius: 16) else const CircleAvatar(radius: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(c.autor?.nombre ?? 'Alguien',
                    overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge),
              ),
              const SizedBox(width: 6),
              Text(cuando, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              const Spacer(),
              if (mio)
                IconButton(
                  tooltip: 'Borrar comentario',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: alBorrar,
                ),
            ]),
            const SizedBox(height: 2),
            SelectableText.rich(TextSpan(children: [
              for (final p in partesDelTexto(c.texto))
                TextSpan(
                  text: p.texto,
                  style: p.mencion ? TextStyle(color: scheme.primary, fontWeight: FontWeight.w600) : null,
                ),
            ])),
          ]),
        ),
      ]),
    );
  }
}
