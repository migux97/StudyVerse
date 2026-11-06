import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/web/guardar_archivo.dart';
import '../../../core/widgets/auth_layout.dart';
import '../../../core/widgets/pagina.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../files/domain/file_item.dart';
import '../../files/domain/files_repository.dart';
import '../../files/presentation/file_actions.dart';
import '../../files/presentation/files_providers.dart';
import '../domain/docx.dart';
import '../domain/documento.dart';
import '../domain/pdf_export.dart';
import '../../comentarios/presentation/comentarios_providers.dart' show citaProvider;
import '../../comentarios/presentation/comentarios_panel.dart';
import 'documentos_providers.dart';
import '../../groups/presentation/groups_providers.dart';

enum _Guardado { alDia, guardando, sinConexion }

/// Cada cuánto se renueva el bloqueo mientras se edita (dura 2 h).
const _renovarBloqueo = Duration(minutes: 30);

/// Documento de StudyVerse: se lee y, con «Editar», se edita como en Word.
/// Mientras editás se guarda solo; al tocar «Listo» (o salir) queda como versión.
class DocumentoScreen extends ConsumerStatefulWidget {
  const DocumentoScreen({super.key, required this.groupId, required this.fileId});
  final String groupId;
  final String fileId;

  @override
  ConsumerState<DocumentoScreen> createState() => _DocumentoScreenState();
}

class _DocumentoScreenState extends ConsumerState<DocumentoScreen> {
  QuillController? _ctrl;
  final _foco = FocusNode();
  final _scroll = ScrollController();
  StreamSubscription<DocChange>? _cambios;
  ContenidoDocumento? _cargado;
  Timer? _espera;
  Timer? _renovacion;

  bool _editando = false;
  bool _terminando = false;

  /// Al abrir se fija una sola vez si ya lo tenías en edición.
  bool _reanudacionRevisada = false;

  /// Lo que se ve es un borrador mío que no quedó como versión.
  bool _recuperado = false;

  /// Hay cambios que todavía no quedaron como versión.
  bool _sinVersion = false;

  /// Hay cambios que todavía no se autoguardaron.
  bool _pendiente = false;

  /// Hay un autoguardado en camino (nunca dos a la vez).
  bool _guardandoAhora = false;
  var _guardado = _Guardado.alDia;
  DateTime? _ultimoGuardado;

  ClaveDocumento get _clave => (groupId: widget.groupId, fileId: widget.fileId);

  /// Se toma al empezar: en dispose ya no se puede usar ref.
  late final DocumentosRepository _docs;

  /// Panel de comentarios abierto al costado (pantallas anchas).
  bool _comentarios = false;

  @override
  void initState() {
    super.initState();
    _docs = ref.read(documentosRepositoryProvider);
    // Queda en "Recientes".
    ref.read(filesRepositoryProvider).marcarVisto(widget.fileId).then((_) {
      if (mounted) ref.invalidate(recientesProvider);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _espera?.cancel();
    _renovacion?.cancel();
    _cambios?.cancel();
    // Lo último que se escribió no se pierde aunque se cierre de golpe.
    if (_editando && _pendiente && _ctrl != null) _docs.guardar(widget.fileId, _ops).ignore();
    _ctrl?.dispose();
    _foco.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<dynamic> get _ops => _ctrl!.document.toDelta().toJson();

  /// Lo que se marca con el mouse o el dedo queda listo para comentarlo citándolo.
  void _alSeleccionar() {
    final c = _ctrl;
    if (c == null || c.selection.isCollapsed || !c.selection.isValid) return;
    final sel = c.selection;
    var texto = c.document.getPlainText(sel.start, sel.end - sel.start).trim().replaceAll(RegExp(r'\s+'), ' ');
    if (texto.isEmpty) return;
    if (texto.length > 500) texto = '${texto.substring(0, 499)}…';
    ref.read(citaProvider(widget.fileId).notifier).poner(texto);
  }

  void _escuchar() {
    _cambios?.cancel();
    _cambios = _ctrl!.document.changes.listen(_alEscribir);
  }

  /// Primera carga (dentro de build: todavía no hay editor que avisar).
  void _crear(ContenidoDocumento c) {
    _cargado = c;
    _recuperado = c.recuperado;
    _ctrl = QuillController(
      document: Document.fromJson(c.ops),
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: true,
    );
    _ctrl!.addListener(_alSeleccionar);
    _escuchar();
  }

  /// En vivo: lo que escribe otro (o la versión nueva) reemplaza lo que se ve.
  /// Solo en lectura, y solo si de verdad cambió.
  void _reemplazar(ContenidoDocumento c) {
    if (_ctrl == null || _editando || _terminando || identical(c, _cargado)) return;
    _cargado = c;
    setState(() {
      _recuperado = c.recuperado;
      _ctrl!.document = Document.fromJson(c.ops);
      _escuchar();
    });
  }

  void _alEscribir(DocChange cambio) {
    if (!_editando || cambio.source != ChangeSource.local) return;
    _pendiente = true;
    _sinVersion = true;
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 1200), _autoguardar);
    if (_guardado != _Guardado.guardando) setState(() => _guardado = _Guardado.guardando);
  }

  Future<void> _autoguardar() async {
    // Uno a la vez: si hay uno en camino, el siguiente sale cuando termine.
    if (!_pendiente || _ctrl == null || !_editando || _guardandoAhora) return;
    _guardandoAhora = true;
    _pendiente = false;
    try {
      final cuando = await _docs.guardar(widget.fileId, _ops);
      if (!mounted) return;
      setState(() {
        _ultimoGuardado = cuando;
        _guardado = _pendiente ? _Guardado.guardando : _Guardado.alDia;
      });
    } on DocumentoFailure catch (e) {
      _pendiente = true;
      if (!mounted) return;
      if (e.sinConexion) {
        setState(() => _guardado = _Guardado.sinConexion);
        _espera = Timer(const Duration(seconds: 5), _autoguardar);
      } else {
        // El servidor no lo acepta (por ejemplo, se venció el tiempo de edición):
        // se deja de editar y se avisa una vez. Lo escrito sigue en pantalla.
        _salirDeEdicion();
        mostrarMensaje(context, e.mensaje, error: true);
      }
    } finally {
      _guardandoAhora = false;
      if (mounted && _pendiente && _editando && _guardado != _Guardado.sinConexion) {
        _espera?.cancel();
        _espera = Timer(const Duration(milliseconds: 300), _autoguardar);
      }
    }
  }

  void _salirDeEdicion() {
    _espera?.cancel();
    _renovacion?.cancel();
    setState(() {
      _editando = false;
      _ctrl?.readOnly = true;
      _guardado = _Guardado.alDia;
    });
  }

  void _empezarEdicion() {
    _renovacion?.cancel();
    final repo = ref.read(filesRepositoryProvider);
    _renovacion = Timer.periodic(_renovarBloqueo, (_) => repo.lock(widget.fileId, 120).catchError((_) {}));
    setState(() {
      _editando = true;
      _ctrl?.readOnly = false;
      // Lo recuperado todavía no es versión: al terminar se guarda.
      if (_recuperado) _sinVersion = true;
    });
    _foco.requestFocus();
  }

  Future<void> _editar(FileItem archivo) async {
    final miId = ref.read(authStateProvider).value?.id;
    if (archivo.estadoBloqueo(miId, DateTime.now()) == EstadoBloqueo.deOtro) return;
    try {
      // También si ya era mío: así se renueva el tiempo.
      await ref.read(filesRepositoryProvider).lock(archivo.id, 120);
    } on FilesFailure catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
      return;
    }
    if (mounted) _empezarEdicion();
  }

  /// Deja lo escrito como versión nueva (que además libera el archivo).
  Future<void> _terminar(FileItem archivo) async {
    if (_terminando) return;
    _espera?.cancel();
    // Mientras se sube, no se puede seguir escribiendo (no quedaría en la versión).
    setState(() {
      _terminando = true;
      _ctrl?.readOnly = true;
    });
    final repo = ref.read(filesRepositoryProvider);
    try {
      if (_sinVersion) {
        final v = await repo.upload(
          groupId: archivo.groupId,
          folderId: archivo.folderId,
          nombre: archivo.nombre,
          bytes: bytesDeOps(_ops),
          fileId: archivo.id,
        );
        if (mounted) mostrarMensaje(context, 'Guardamos la versión ${v.versionNumber}');
      } else {
        await repo.unlock(archivo.id);
      }
      _pendiente = false;
      _sinVersion = false;
      _recuperado = false;
      if (!mounted) return;
      _salirDeEdicion();
      ref.invalidate(fileProvider(_clave));
    } catch (e) {
      if (!mounted) return;
      setState(() => _ctrl?.readOnly = false);
      mostrarMensaje(context, e is FilesFailure ? e.mensaje : 'No pudimos guardar la versión. Probá de nuevo',
          error: true);
    } finally {
      if (mounted) setState(() => _terminando = false);
    }
  }

  Future<void> _exportar(FileItem archivo, {required bool pdf}) async {
    final ops = _ops;
    final nombre = archivo.visible;
    try {
      final ok = pdf
          ? await guardarEnDispositivo(await exportarPdf(ops, titulo: nombre), '$nombre.pdf', mimePdf)
          : await guardarEnDispositivo(exportarDocx(ops), '$nombre.docx', mimeDocx);
      if (ok && mounted) mostrarMensaje(context, pdf ? 'Descargamos el PDF' : 'Descargamos el archivo de Word');
    } catch (_) {
      if (mounted) mostrarMensaje(context, 'No pudimos armar el archivo. Probá de nuevo', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final archivo = ref.watch(fileProvider(_clave));
    final contenido = ref.watch(contenidoDocumentoProvider(_clave));
    // Mantiene la cita mientras el documento está abierto (sin reconstruirlo).
    ref.listen(citaProvider(widget.fileId), (_, _) {});
    ref.listen(contenidoDocumentoProvider(_clave), (_, next) {
      if (next.hasValue) _reemplazar(next.requireValue);
    });
    final miId = ref.watch(authStateProvider).value?.id;
    final a = archivo.value;
    if (_ctrl == null && contenido.hasValue) _crear(contenido.requireValue);
    final estado = a?.estadoBloqueo(miId, DateTime.now());

    // Si al abrir ya lo tengo bloqueado (lo acabo de crear o lo dejé abierto), sigo editando.
    if (a != null && _ctrl != null && !_reanudacionRevisada) {
      _reanudacionRevisada = true;
      if (estado == EstadoBloqueo.mio) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_editando) _empezarEdicion();
        });
      }
    }

    return PopScope(
      canPop: !_editando,
      onPopInvokedWithResult: (salio, _) async {
        if (salio || a == null) return;
        await _terminar(a);
        if (mounted && !_editando) _volver();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () async {
            if (_editando && a != null) await _terminar(a);
            if (mounted && !_editando) _volver();
          }),
          titleSpacing: 0,
          title: a == null
              ? null
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.visible, overflow: TextOverflow.ellipsis),
                  _Estado(
                    recuperado: _recuperado && !_editando,
                    editando: _editando,
                    guardado: _guardado,
                    ultimo: _ultimoGuardado,
                    otro: estado == EstadoBloqueo.deOtro ? a.lockedByNombre : null,
                  ),
                ]),
          actions: [
            if (a != null && _editando)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: FilledButton.tonalIcon(
                  icon: _terminando
                      ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_rounded),
                  label: const Text('Listo'),
                  onPressed: _terminando ? null : () => _terminar(a),
                ),
              )
            else if (a != null && estado != EstadoBloqueo.deOtro && !ref.watch(soloLecturaProvider(a.groupId)))
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: FilledButton.icon(
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar'),
                  onPressed: _ctrl == null ? null : () => _editar(a),
                ),
              ),
            if (a != null)
              BotonComentarios(
                groupId: a.groupId,
                fileId: a.id,
                alAlternarPanel: MediaQuery.sizeOf(context).width >= 1100
                    ? () => setState(() => _comentarios = !_comentarios)
                    : null,
              ),
            if (a != null)
              PopupMenuButton<String>(
                tooltip: 'Más opciones',
                onSelected: (op) => switch (op) {
                  'word' => _exportar(a, pdf: false),
                  'pdf' => _exportar(a, pdf: true),
                  'historial' => verHistorial(context, a),
                  _ => null,
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'word', child: ListTile(leading: Icon(Icons.description_outlined), title: Text('Descargar como Word'))),
                  PopupMenuItem(value: 'pdf', child: ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('Descargar como PDF'))),
                  PopupMenuItem(value: 'historial', child: ListTile(leading: Icon(Icons.history), title: Text('Historial de versiones'))),
                ],
              ),
          ],
        ),
        body: switch ((archivo, contenido)) {
          (AsyncError(), _) || (_, AsyncError()) when _ctrl == null =>
            const SinVista(motivo: 'No pudimos abrir el documento. Revisá tu conexión.'),
          _ when _ctrl == null => const Center(child: CircularProgressIndicator()),
          _ => Column(children: [
              if (_editando) _BarraFormato(controller: _ctrl!),
              if (estado == EstadoBloqueo.deOtro && a != null) _AvisoOtro(archivo: a),
              Expanded(
                child: Row(children: [
                  Expanded(
                    child: PaginaDocumento(
                  scrollController: _scroll,
                  alTocarFondo: _editando ? _foco.requestFocus : null,
                  child: QuillEditor(
                    controller: _ctrl!,
                    focusNode: _foco,
                    scrollController: _scroll,
                    config: QuillEditorConfig(
                      placeholder: _editando ? 'Empezá a escribir…' : null,
                      showCursor: _editando,
                      scrollable: false,
                      expands: false,
                    ),
                  ),
                    ),
                  ),
                  if (_comentarios && a != null && MediaQuery.sizeOf(context).width >= 1100) ...[
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: 360,
                      child: ComentariosPanel(
                        groupId: a.groupId,
                        fileId: a.id,
                        alCerrar: () => setState(() => _comentarios = false),
                      ),
                    ),
                  ],
                ]),
              ),
            ]),
        },
      ),
    );
  }

  void _volver() => context.canPop() ? context.pop() : context.go(Routes.grupo(widget.groupId));
}

class _Estado extends StatelessWidget {
  const _Estado({required this.editando, required this.guardado, this.ultimo, this.otro, this.recuperado = false});
  final bool editando;
  final bool recuperado;
  final _Guardado guardado;
  final DateTime? ultimo;
  final String? otro;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icono, texto) = otro != null
        ? (Icons.lock_outline, '$otro está editando · lo ves en vivo')
        : recuperado
            ? (Icons.restore, 'Recuperamos lo que no terminaste · tocá Editar para guardarlo')
            : !editando
                ? (Icons.visibility_outlined, 'Solo lectura')
                : switch (guardado) {
                    _Guardado.guardando => (Icons.sync, 'Guardando…'),
                    _Guardado.sinConexion => (Icons.cloud_off_outlined, 'Sin conexión, lo guardamos cuando vuelva'),
                    _Guardado.alDia => (Icons.cloud_done_outlined, ultimo == null ? 'Editando' : 'Guardado'),
                  };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icono, size: 14, color: scheme.onSurfaceVariant),
      const SizedBox(width: 4),
      Flexible(
        child: Text(texto,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ),
    ]);
  }
}

/// Barra de formato: en pantallas anchas en varias filas; en el celular, una
/// sola fila que se desliza.
class _BarraFormato extends StatelessWidget {
  const _BarraFormato({required this.controller});
  final QuillController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ancho = MediaQuery.sizeOf(context).width >= 900;
    return Material(
      color: scheme.surfaceContainerLow,
      child: Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outlineVariant))),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        alignment: Alignment.center,
        child: QuillSimpleToolbar(
          controller: controller,
          config: QuillSimpleToolbarConfig(
            multiRowsDisplay: ancho,
            showAlignmentButtons: true,
            showFontFamily: false,
            showFontSize: false,
            showInlineCode: false,
            showCodeBlock: false,
            showSubscript: false,
            showSuperscript: false,
            showSearchButton: false,
            showDirection: false,
          ),
        ),
      ),
    );
  }
}

class _AvisoOtro extends ConsumerWidget {
  const _AvisoOtro({required this.archivo});
  final FileItem archivo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final miId = ref.watch(authStateProvider).value?.id;
    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(children: [
          Icon(Icons.lock_outline, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text('${archivo.lockedByNombre ?? 'Alguien'} lo está editando. Ves los cambios en vivo.',
                style: TextStyle(color: scheme.onSecondaryContainer)),
          ),
          if (!archivo.pedidoPor(miId))
            TextButton(onPressed: () => pedirLiberacion(context, ref, archivo), child: const Text('Pedir que lo libere')),
        ]),
      ),
    );
  }
}
