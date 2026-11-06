import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/auth_layout.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../auth/domain/profile.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/presentation/user_avatar.dart';
import '../../comentarios/domain/comentario.dart' show completarMencion, mencionEnCurso, partesDelTexto;
import '../../files/domain/file_item.dart' show FileKind, fileKindFor, nombreVisible;
import '../../files/presentation/file_icon.dart';
import '../../groups/domain/group.dart';
import '../../groups/presentation/group_shell.dart';
import '../../groups/presentation/groups_providers.dart';
import '../domain/mensaje.dart';
import 'chat_providers.dart';

/// Chat del grupo: solo los integrantes (el docente no lo ve).
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context) => GroupLoader(
        groupId: groupId,
        builder: (g) => GroupShell(
          grupo: g,
          seccion: SeccionGrupo.chat,
          body: g.soloLectura
              ? const Aviso(icono: Icons.lock_outline, texto: 'El chat es solo para los integrantes del grupo')
              : _Chat(grupo: g),
        ),
      );
}

class _Chat extends ConsumerStatefulWidget {
  const _Chat({required this.grupo});
  final Group grupo;

  @override
  ConsumerState<_Chat> createState() => _ChatState();
}

class _ChatState extends ConsumerState<_Chat> {
  final _texto = TextEditingController();
  final _foco = FocusNode();
  final _scroll = ScrollController();
  Mensaje? _respondiendo;
  Mensaje? _editando;
  ({String id, String nombre})? _adjunto;
  bool _enviando = false;
  List<Profile> _sugerencias = const [];

  String get _groupId => widget.grupo.id;

  @override
  void initState() {
    super.initState();
    _texto.addListener(_buscarMencion);
    _scroll.addListener(() {
      // La lista va al revés: "arriba de todo" es el final del scroll.
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        ref.read(chatProvider(_groupId).notifier).cargarMas();
      }
    });
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
    final miembros = ref.read(groupMembersProvider(_groupId)).value ?? const [];
    final nuevas = enCurso == null
        ? const <Profile>[]
        : [
            for (final m in miembros)
              if (m.profile.id != miId &&
                  m.profile.username != null &&
                  (m.profile.username!.toLowerCase().startsWith(enCurso.buscado) ||
                      m.profile.nombre.toLowerCase().contains(enCurso.buscado)))
                m.profile,
          ].take(3).toList();
    final antes = {for (final p in _sugerencias) p.id};
    if (nuevas.length != antes.length || !nuevas.every((p) => antes.contains(p.id))) {
      setState(() => _sugerencias = nuevas);
    }
  }

  void _elegirMencion(Profile p) {
    final enCurso = mencionEnCurso(_texto.text, _texto.selection.baseOffset);
    if (enCurso == null || p.username == null) return;
    final r = completarMencion(_texto.text, enCurso.inicio, _texto.selection.baseOffset, p.username!);
    _texto.value = TextEditingValue(text: r.texto, selection: TextSelection.collapsed(offset: r.cursor));
    _foco.requestFocus();
  }

  Future<void> _enviar() async {
    final texto = _texto.text.trim();
    if (_enviando || (texto.isEmpty && _adjunto == null)) return;
    if (texto.length > 4000) return mostrarMensaje(context, 'Es muy largo: usá hasta 4000 caracteres');
    setState(() => _enviando = true);
    final repo = ref.read(chatRepositoryProvider);
    final chat = ref.read(chatProvider(_groupId).notifier);
    try {
      final Mensaje m;
      if (_editando case final e?) {
        if (texto.isEmpty) return mostrarMensaje(context, 'El mensaje no puede quedar vacío');
        m = await repo.editar(e.id, texto);
      } else {
        m = await repo.enviar(
          groupId: _groupId,
          texto: texto.isEmpty ? null : texto,
          fileId: _adjunto?.id,
          respondeA: _respondiendo?.id,
        );
      }
      if (!mounted) return;
      // Se muestra ya, aunque el aviso en vivo tarde (o no llegue).
      await chat.poner(m);
      if (!mounted) return;
      _texto.clear();
      setState(() {
        _respondiendo = null;
        _editando = null;
        _adjunto = null;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } on ChatFailure catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _elegirArchivo() async {
    final List<({String id, String nombre})> archivos;
    try {
      archivos = await ref.read(chatRepositoryProvider).archivos(_groupId);
    } on ChatFailure catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
      return;
    }
    if (!mounted) return;
    if (archivos.isEmpty) return mostrarMensaje(context, 'El grupo todavía no tiene archivos');
    final elegido = await showModalBottomSheet<({String id, String nombre})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              title: const Text('Adjuntar un archivo del grupo'),
              subtitle: archivos.length >= 300 ? const Text('Se muestran los primeros 300, por nombre') : null,
            ),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final a in archivos)
                  ListTile(
                    leading: FileIcon(kind: fileKindFor(a.nombre)),
                    title: Text(nombreVisible(a.nombre), overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(ctx, a),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
    if (elegido != null && mounted) {
      setState(() => _adjunto = elegido);
      _foco.requestFocus();
    }
  }

  Future<void> _acciones(Mensaje m, bool mio) async {
    final puedeBorrar = mio || widget.grupo.soyAdmin;
    final accion = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.reply), title: const Text('Responder'), onTap: () => Navigator.pop(ctx, 'responder')),
          if (m.texto != null)
            ListTile(leading: const Icon(Icons.copy), title: const Text('Copiar texto'), onTap: () => Navigator.pop(ctx, 'copiar')),
          if (mio && m.texto != null)
            ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Editar'), onTap: () => Navigator.pop(ctx, 'editar')),
          if (puedeBorrar)
            ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Eliminar'), onTap: () => Navigator.pop(ctx, 'borrar')),
        ]),
      ),
    );
    if (!mounted) return;
    switch (accion) {
      case 'responder':
        setState(() {
          _respondiendo = m;
          _editando = null;
        });
        _foco.requestFocus();
      case 'copiar':
        await Clipboard.setData(ClipboardData(text: m.texto!));
        if (mounted) mostrarMensaje(context, 'Texto copiado');
      case 'editar':
        setState(() {
          _editando = m;
          _respondiendo = null;
          _adjunto = null;
        });
        _texto.value = TextEditingValue(text: m.texto!, selection: TextSelection.collapsed(offset: m.texto!.length));
        _foco.requestFocus();
      case 'borrar':
        final ok = await confirmar(context,
            titulo: '¿Eliminar el mensaje?', mensaje: 'Se va a ver como "Mensaje eliminado".', accion: 'Eliminar', peligroso: true);
        if (!ok || !mounted) return;
        try {
          final repo = ref.read(chatRepositoryProvider);
          await repo.borrar(m.id);
          final borrado = await repo.mensaje(m.id);
          if (borrado != null && mounted) await ref.read(chatProvider(_groupId).notifier).poner(borrado);
        } on ChatFailure catch (e) {
          if (mounted) mostrarMensaje(context, e.mensaje, error: true);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(chatProvider(_groupId));
    // Para tener los integrantes a mano cuando se escriba @.
    ref.watch(groupMembersProvider(_groupId));
    final miId = ref.watch(authStateProvider).value?.id;

    final cuerpo = switch (estado) {
      EstadoChat(cargando: true) => const Center(child: CircularProgressIndicator()),
      EstadoChat(error: final String e) => Aviso(
          icono: Icons.cloud_off_outlined,
          texto: e,
          accion: FilledButton(
              onPressed: () => ref.read(chatProvider(_groupId).notifier).reintentar(), child: const Text('Reintentar')),
        ),
      EstadoChat(mensajes: final ms) when ms.isEmpty => const Aviso(
          icono: Icons.forum_outlined,
          texto: 'Todavía no hay mensajes',
          detalle: 'Coordinen el TP acá: mencioná a alguien con @ para avisarle, o adjuntá un archivo del grupo.',
        ),
      _ => _lista(estado, miId),
    };

    return Column(children: [
      Expanded(child: cuerpo),
      _Redactor(
        texto: _texto,
        foco: _foco,
        enviando: _enviando,
        respondiendo: _respondiendo,
        editando: _editando,
        adjunto: _adjunto,
        sugerencias: _sugerencias,
        onElegirMencion: _elegirMencion,
        onEnviar: _enviar,
        onAdjuntar: _editando == null ? _elegirArchivo : null,
        onCancelar: () {
          setState(() {
            if (_editando != null) _texto.clear();
            _respondiendo = null;
            _editando = null;
          });
        },
        onQuitarAdjunto: () => setState(() => _adjunto = null),
      ),
    ]);
  }

  Widget _lista(EstadoChat estado, String? miId) {
    // Si los mensajes no llenan la pantalla no hay scroll que pida los anteriores.
    if (estado.hayMas && !estado.cargandoMas) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients && _scroll.position.maxScrollExtent <= 0) {
          ref.read(chatProvider(_groupId).notifier).cargarMas();
        }
      });
    }
    final filas = armarFilas(estado.mensajes, leidoHasta: estado.leidoAlEntrar, miId: miId).reversed.toList();
    final ahora = DateTime.now();
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView.builder(
          controller: _scroll,
          reverse: true,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          itemCount: filas.length + (estado.cargandoMas ? 1 : 0),
          itemBuilder: (_, i) {
            if (i == filas.length) {
              return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
            }
            return switch (filas[i]) {
              FilaDia(:final dia) => _Separador(texto: tituloDia(dia, ahora)),
              FilaNuevos() => const _Separador(texto: 'Mensajes nuevos', resaltado: true),
              FilaMensaje(:final mensaje, :final seguido) => _Burbuja(
                  mensaje: mensaje,
                  mio: mensaje.autorId == miId,
                  seguido: seguido,
                  conBotonOpciones: MediaQuery.sizeOf(context).width >= 600,
                  onAcciones: mensaje.borrado ? null : () => _acciones(mensaje, mensaje.autorId == miId),
                  onAbrirArchivo: mensaje.fileId == null
                      ? null
                      : () => context.push(fileKindFor(mensaje.archivoNombre ?? '') == FileKind.studyverse
                          ? Routes.documento(_groupId, mensaje.fileId!)
                          : Routes.archivo(_groupId, mensaje.fileId!)),
                ),
            };
          },
        ),
      ),
    );
  }
}

class _Separador extends StatelessWidget {
  const _Separador({required this.texto, this.resaltado = false});
  final String texto;
  final bool resaltado;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = resaltado ? scheme.primary : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Expanded(child: Divider(color: resaltado ? scheme.primary : null)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(texto, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
        ),
        Expanded(child: Divider(color: resaltado ? scheme.primary : null)),
      ]),
    );
  }
}

class _Burbuja extends StatelessWidget {
  const _Burbuja({
    required this.mensaje,
    required this.mio,
    required this.seguido,
    required this.conBotonOpciones,
    required this.onAcciones,
    required this.onAbrirArchivo,
  });

  final Mensaje mensaje;
  final bool mio;
  final bool seguido;

  /// En PC; en el celular alcanza con mantener apretado.
  final bool conBotonOpciones;
  final VoidCallback? onAcciones;
  final VoidCallback? onAbrirArchivo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m = mensaje;
    final hora = TimeOfDay.fromDateTime(m.createdAt.toLocal()).format(context);
    final fondo = mio ? scheme.primaryContainer : scheme.surfaceContainerHigh;
    final colorTexto = mio ? scheme.onPrimaryContainer : scheme.onSurface;
    final gris = theme.textTheme.bodySmall?.copyWith(color: colorTexto.withValues(alpha: 0.7));

    final contenido = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!mio && !seguido)
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(m.autor?.nombre ?? 'Ex integrante',
              style: theme.textTheme.labelMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600)),
        ),
      if (m.cita case final c? when !m.borrado)
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          decoration: BoxDecoration(
            color: colorTexto.withValues(alpha: 0.06),
            border: Border(left: BorderSide(color: scheme.primary, width: 3)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.autorNombre ?? 'Alguien', style: theme.textTheme.labelSmall?.copyWith(color: scheme.primary)),
            Text(c.borrado ? 'Mensaje eliminado' : (c.texto ?? 'Archivo'),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: gris),
          ]),
        ),
      if (m.borrado)
        Text('Mensaje eliminado', style: gris?.copyWith(fontStyle: FontStyle.italic))
      else ...[
        if (m.fileId != null)
          InkWell(
            onTap: onAbrirArchivo,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: scheme.surface.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                FileIcon(kind: fileKindFor(m.archivoNombre ?? ''), size: 22),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(nombreVisible(m.archivoNombre ?? 'Archivo'),
                      overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(color: colorTexto)),
                ),
              ]),
            ),
          ),
        if (m.texto case final t?)
          Text.rich(
            TextSpan(children: [
              for (final p in partesDelTexto(t))
                TextSpan(
                  text: p.texto,
                  style: p.mencion ? TextStyle(color: scheme.primary, fontWeight: FontWeight.w600) : null,
                ),
            ]),
            style: theme.textTheme.bodyMedium?.copyWith(color: colorTexto),
          ),
      ],
      Align(
        alignment: Alignment.bottomRight,
        child: Text(m.editado ? 'editado · $hora' : hora, style: gris?.copyWith(fontSize: 11)),
      ),
    ]);

    final burbuja = Flexible(
      child: GestureDetector(
        onLongPress: onAcciones,
        onSecondaryTap: onAcciones,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
          decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(14)),
          child: contenido,
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: seguido ? 2 : 8),
      child: Row(
        mainAxisAlignment: mio ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mio)
            SizedBox(
              width: 40,
              child: seguido || m.autor == null
                  ? null
                  : Align(alignment: Alignment.bottomLeft, child: UserAvatar(profile: m.autor!, radius: 15)),
            ),
          burbuja,
          if (onAcciones != null && conBotonOpciones)
            IconButton(
              tooltip: 'Opciones del mensaje',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              icon: const Icon(Icons.more_vert),
              onPressed: onAcciones,
            ),
        ],
      ),
    );
  }
}

/// Abajo de todo: lo que se está escribiendo, la cita, el adjunto y las
/// sugerencias de @. Enter manda; Shift+Enter hace un salto de línea.
class _Redactor extends StatelessWidget {
  const _Redactor({
    required this.texto,
    required this.foco,
    required this.enviando,
    required this.respondiendo,
    required this.editando,
    required this.adjunto,
    required this.sugerencias,
    required this.onElegirMencion,
    required this.onEnviar,
    required this.onAdjuntar,
    required this.onCancelar,
    required this.onQuitarAdjunto,
  });

  final TextEditingController texto;
  final FocusNode foco;
  final bool enviando;
  final Mensaje? respondiendo;
  final Mensaje? editando;
  final ({String id, String nombre})? adjunto;
  final List<Profile> sugerencias;
  final void Function(Profile) onElegirMencion;
  final VoidCallback onEnviar;
  final VoidCallback? onAdjuntar;
  final VoidCallback onCancelar;
  final VoidCallback onQuitarAdjunto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final contexto = editando != null
        ? ('Editando el mensaje', null as String?)
        : respondiendo != null
            ? ('Respondiendo a ${respondiendo!.autor?.nombre ?? 'Alguien'}', respondiendo!.texto ?? 'Archivo')
            : null;

    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (sugerencias.isNotEmpty)
                Column(children: [
                  for (final p in sugerencias)
                    ListTile(
                      dense: true,
                      leading: UserAvatar(profile: p, radius: 14),
                      title: Text(p.nombre),
                      subtitle: Text('@${p.username}'),
                      onTap: () => onElegirMencion(p),
                    ),
                ]),
              if (contexto != null)
                ListTile(
                  dense: true,
                  leading: Icon(editando != null ? Icons.edit_outlined : Icons.reply, color: scheme.primary),
                  title: Text(contexto.$1, style: TextStyle(color: scheme.primary)),
                  subtitle: contexto.$2 == null ? null : Text(contexto.$2!, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(tooltip: 'Cancelar', icon: const Icon(Icons.close), onPressed: onCancelar),
                ),
              if (adjunto case final a?)
                ListTile(
                  dense: true,
                  leading: FileIcon(kind: fileKindFor(a.nombre)),
                  title: Text(nombreVisible(a.nombre), overflow: TextOverflow.ellipsis),
                  trailing: IconButton(tooltip: 'Quitar archivo', icon: const Icon(Icons.close), onPressed: onQuitarAdjunto),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  if (onAdjuntar != null)
                    IconButton(tooltip: 'Adjuntar un archivo del grupo', icon: const Icon(Icons.attach_file), onPressed: onAdjuntar),
                  Expanded(
                    child: Focus(
                      onKeyEvent: (_, e) {
                        final enter = e.logicalKey == LogicalKeyboardKey.enter ||
                            e.logicalKey == LogicalKeyboardKey.numpadEnter;
                        if (e is! KeyDownEvent || !enter || HardwareKeyboard.instance.isShiftPressed) {
                          return KeyEventResult.ignored;
                        }
                        // Con sugerencias abiertas, Enter elige la primera.
                        if (sugerencias.isNotEmpty) {
                          onElegirMencion(sugerencias.first);
                        } else {
                          onEnviar();
                        }
                        return KeyEventResult.handled;
                      },
                      child: TextField(
                        controller: texto,
                        focusNode: foco,
                        minLines: 1,
                        maxLines: 6,
                        textCapitalization: TextCapitalization.sentences,
                        inputFormatters: [LengthLimitingTextInputFormatter(4000)],
                        decoration: const InputDecoration(
                          hintText: 'Escribí un mensaje… (@ para mencionar)',
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    tooltip: editando != null ? 'Guardar' : 'Enviar',
                    onPressed: enviando ? null : onEnviar,
                    icon: enviando
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(editando != null ? Icons.check : Icons.send),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
