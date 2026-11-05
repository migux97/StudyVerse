import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/auth_layout.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../documentos/domain/documento.dart';
import '../../files/domain/file_item.dart';
import '../../files/domain/files_repository.dart';
import '../../files/presentation/file_actions.dart';
import '../../files/presentation/file_icon.dart';
import '../../files/presentation/files_providers.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../comentarios/presentation/comentarios_panel.dart';
import 'visor_providers.dart';
import 'vistas.dart';
import '../../groups/presentation/groups_providers.dart';

/// Abre un archivo dentro de la app: los documentos de StudyVerse en el
/// editor; el resto, en el visor.
void abrirArchivo(BuildContext context, FileItem archivo) => context.push(
      archivo.kind == FileKind.studyverse
          ? Routes.documento(archivo.groupId, archivo.id)
          : Routes.archivo(archivo.groupId, archivo.id),
    );

const _extensionesTexto = {'txt', 'md', 'tex', 'csv'};

String _extension(String nombre) {
  final i = nombre.lastIndexOf('.');
  return i < 0 ? '' : nombre.substring(i + 1).toLowerCase();
}

/// Vista previa de cualquier archivo, como la de Drive: arriba el nombre y
/// las acciones; abajo el contenido.
class VisorScreen extends ConsumerStatefulWidget {
  const VisorScreen({super.key, required this.groupId, required this.fileId});
  final String groupId;
  final String fileId;

  @override
  ConsumerState<VisorScreen> createState() => _VisorScreenState();
}

class _VisorScreenState extends ConsumerState<VisorScreen> {
  /// Texto que se está editando (archivos de texto y código).
  TextEditingController? _edicion;
  String _original = '';
  bool _guardando = false;

  /// Panel de comentarios abierto al costado (pantallas anchas).
  bool _comentarios = false;

  @override
  void initState() {
    super.initState();
    // Queda en "Recientes".
    ref.read(filesRepositoryProvider).marcarVisto(widget.fileId).then((_) {
      if (mounted) ref.invalidate(recientesProvider);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _edicion?.dispose();
    super.dispose();
  }

  bool _editable(FileItem a) =>
      a.kind == FileKind.codigo || (a.kind == FileKind.texto) || _extensionesTexto.contains(_extension(a.nombre));

  Future<void> _editarTexto(FileItem a, String texto) async {
    final miId = ref.read(authStateProvider).value?.id;
    final estado = a.estadoBloqueo(miId, DateTime.now());
    if (estado == EstadoBloqueo.deOtro) {
      return mostrarMensaje(context, '${a.lockedByNombre ?? 'Alguien'} lo está editando');
    }
    try {
      if (estado == EstadoBloqueo.libre) await ref.read(filesRepositoryProvider).lock(a.id, 120);
    } on FilesFailure catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
      return;
    }
    if (mounted) {
      setState(() {
        _original = texto;
        _edicion = TextEditingController(text: texto);
      });
    }
  }

  void _cerrarEdicion() {
    final c = _edicion;
    setState(() => _edicion = null);
    // Se libera cuando el campo ya no está en pantalla.
    WidgetsBinding.instance.addPostFrameCallback((_) => c?.dispose());
  }

  Future<void> _guardarTexto(FileItem a) async {
    setState(() => _guardando = true);
    try {
      final v = await ref.read(filesRepositoryProvider).upload(
            groupId: a.groupId,
            folderId: a.folderId,
            nombre: a.nombre,
            bytes: utf8.encode(_edicion!.text),
            fileId: a.id,
          );
      if (!mounted) return;
      _cerrarEdicion();
      mostrarMensaje(context, 'Guardamos la versión ${v.versionNumber}');
    } on FilesFailure catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _descartarTexto(FileItem a) async {
    if (_edicion != null && _edicion!.text != _original) {
      final ok = await confirmar(
        context,
        titulo: '¿Descartar los cambios?',
        mensaje: 'Lo que escribiste no se va a guardar.',
        accion: 'Descartar',
        peligroso: true,
      );
      if (!ok || !mounted) return;
    }
    _cerrarEdicion();
    try {
      await ref.read(filesRepositoryProvider).unlock(a.id);
    } on FilesFailure {
      // Vence solo.
    }
  }

  /// .docx → documento de StudyVerse en la misma carpeta, y lo abre.
  Future<void> _convertirDocx(FileItem a, List<Map<String, dynamic>> ops) async {
    final base = a.nombre.replaceAll(RegExp(r'\.[^.]+$'), '');
    final hermanos = await ref.read(filesProvider((groupId: a.groupId, folderId: a.folderId)).future);
    final usados = hermanos.map((f) => f.nombre.toLowerCase()).toSet();
    var nombre = '$base.$extensionDocumento';
    for (var n = 2; usados.contains(nombre.toLowerCase()); n++) {
      nombre = '$base ($n).$extensionDocumento';
    }
    try {
      final v = await ref.read(filesRepositoryProvider).upload(
            groupId: a.groupId,
            folderId: a.folderId,
            nombre: nombre,
            bytes: bytesDeOps(ops),
            nota: 'Creado a partir de ${a.nombre}',
          );
      if (!mounted) return;
      mostrarMensaje(context, 'Creamos «${nombreVisible(nombre)}» para que lo edites');
      context.pushReplacement(Routes.documento(a.groupId, v.fileId));
    } on FilesFailure catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final archivo = ref.watch(fileProvider((groupId: widget.groupId, fileId: widget.fileId)));
    return archivo.when(
      skipLoadingOnReload: true,
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(leading: BackButton(onPressed: _volver)),
        body: SinVista(motivo: e is FilesFailure ? e.mensaje : 'No pudimos abrir el archivo'),
      ),
      data: (a) => _pantalla(context, a),
    );
  }

  void _volver() => context.canPop() ? context.pop() : context.go(Routes.grupo(widget.groupId));

  Widget _pantalla(BuildContext context, FileItem a) {
    final v = a.current;
    final scheme = Theme.of(context).colorScheme;
    final editando = _edicion != null;
    final descargar = IconButton(
      tooltip: 'Descargar',
      icon: const Icon(Icons.download_outlined),
      onPressed: v == null ? null : () => abrirVersion(context, ref, v, a.nombre, descargar: true),
    );

    return PopScope(
      canPop: !editando,
      onPopInvokedWithResult: (salio, _) {
        if (!salio) _descartarTexto(a);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: editando ? () => _descartarTexto(a) : _volver),
          titleSpacing: 0,
          title: Row(children: [
            FileIcon(kind: a.kind, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.visible, overflow: TextOverflow.ellipsis),
                if (v != null)
                  Text(
                    editando ? 'Editando · se guarda como versión nueva' : 'v${v.versionNumber} · ${formatBytes(v.sizeBytes)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ]),
            ),
          ]),
          actions: [
            if (editando) ...[
              TextButton(onPressed: _guardando ? null : () => _descartarTexto(a), child: const Text('Descartar')),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
                  onPressed: _guardando ? null : () => _guardarTexto(a),
                  child: const Text('Guardar'),
                ),
              ),
            ] else ...[
              BotonComentarios(
                groupId: a.groupId,
                fileId: a.id,
                alAlternarPanel: MediaQuery.sizeOf(context).width >= 1100
                    ? () => setState(() => _comentarios = !_comentarios)
                    : null,
              ),
              descargar,
              PopupMenuButton<String>(
                tooltip: 'Más opciones',
                onSelected: (op) => switch (op) {
                  'pestana' => v == null ? null : abrirVersion(context, ref, v, a.nombre, descargar: false),
                  'historial' => verHistorial(context, a),
                  _ => null,
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'pestana', child: ListTile(leading: Icon(Icons.open_in_new), title: Text('Abrir en otra pestaña'))),
                  PopupMenuItem(value: 'historial', child: ListTile(leading: Icon(Icons.history), title: Text('Historial de versiones'))),
                ],
              ),
            ],
          ],
        ),
        body: _conPanel(
          context,
          a,
          v == null
              ? const SinVista(motivo: 'Este archivo todavía no tiene versiones.')
              : editando
                  ? _EditorTexto(controller: _edicion!, codigo: a.kind == FileKind.codigo)
                  : _contenido(context, a, v),
        ),
      ),
    );
  }

  /// En pantallas anchas, los comentarios al costado del archivo.
  Widget _conPanel(BuildContext context, FileItem a, Widget cuerpo) {
    if (!_comentarios || MediaQuery.sizeOf(context).width < 1100) return cuerpo;
    return Row(children: [
      Expanded(child: cuerpo),
      const VerticalDivider(width: 1),
      SizedBox(
        width: 360,
        child: ComentariosPanel(
          groupId: a.groupId,
          fileId: a.id,
          alCerrar: () => setState(() => _comentarios = false),
        ),
      ),
    ]);
  }

  Widget _contenido(BuildContext context, FileItem a, FileVersion v) {
    final ext = _extension(a.nombre);
    Widget sinVista([String motivo = 'No hay vista previa para este tipo de archivo.']) => SinVista(
          motivo: motivo,
          accion: FilledButton.icon(
            icon: const Icon(Icons.download_outlined),
            label: const Text('Descargar'),
            onPressed: () => abrirVersion(context, ref, v, a.nombre, descargar: true),
          ),
        );
    Widget conValor<T>(AsyncValue<T> valor, Widget Function(T) builder) => valor.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => sinVista('No pudimos abrir el archivo. Revisá tu conexión.'),
          data: builder,
        );

    // Video y audio se reproducen de a pedazos: no importa el tamaño.
    if (a.kind == FileKind.video || a.kind == FileKind.audio) {
      return conValor(
        ref.watch(urlMediaProvider(v)),
        (url) => VistaMedia(key: ValueKey(v.id), url: url, audio: a.kind == FileKind.audio),
      );
    }
    if (v.sizeBytes > maxBytesVistaPrevia) {
      return sinVista('Es muy grande para verlo acá. Descargalo para abrirlo.');
    }

    switch (a.kind) {
      case FileKind.imagen when {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'}.contains(ext):
        return ConBytes(version: v, builder: (b) => VistaImagen(bytes: b));
      case FileKind.pdf:
        return ConBytes(version: v, builder: (b) => VistaPdf(key: ValueKey(v.id), bytes: b, nombre: a.nombre));
      case FileKind.planilla when ext == 'csv':
        return conValor(ref.watch(csvProvider((v: v, nombre: a.visible))), (h) => VistaPlanilla(hojas: [h]));
      case FileKind.planilla when ext == 'xlsx':
        return conValor(ref.watch(xlsxProvider(v)), (h) => h == null ? sinVista() : VistaPlanilla(hojas: h));
      case FileKind.presentacion when ext == 'pptx':
        return conValor(ref.watch(pptxProvider(v)), (d) => d == null ? sinVista() : VistaPresentacion(diapositivas: d));
      case FileKind.documento when ext == 'docx':
        return conValor(ref.watch(docxProvider(v)), (ops) {
          if (ops == null) return sinVista();
          return Column(children: [
            if (ref.watch(soloLecturaProvider(a.groupId)))
              const _Aviso(texto: 'Vista de un archivo de Word.', accion: SizedBox.shrink())
            else
              _Aviso(
                texto: 'Vista de un archivo de Word. Para cambiarlo, hacé una copia editable.',
                accion: TextButton.icon(
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Editar en StudyVerse'),
                  onPressed: () => _convertirDocx(a, ops),
                ),
              ),
            Expanded(child: VistaDocumento(key: ValueKey(v.id), ops: ops)),
          ]);
        });
      case _ when _editable(a):
        return conValor(ref.watch(textoProvider(v)), (t) => Column(children: [
              _Aviso(
                texto: t.cortado
                    ? 'Es largo: mostramos el principio. Descargalo para verlo entero.'
                    : ref.watch(soloLecturaProvider(a.groupId))
                        ? 'Archivo de texto.'
                        : 'Archivo de texto: lo podés cambiar acá.',
                accion: t.cortado || ref.watch(soloLecturaProvider(a.groupId))
                    ? const SizedBox.shrink()
                    : TextButton.icon(
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Editar'),
                        onPressed: () => _editarTexto(a, t.texto),
                      ),
              ),
              Expanded(child: VistaTexto(texto: t.texto, codigo: a.kind == FileKind.codigo)),
            ]));
      default:
        return sinVista();
    }
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto, required this.accion});
  final String texto;
  final Widget accion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(children: [
          Expanded(child: Text(texto, style: TextStyle(color: scheme.onSurfaceVariant))),
          accion,
        ]),
      ),
    );
  }
}

class _EditorTexto extends StatelessWidget {
  const _EditorTexto({required this.controller, required this.codigo});
  final TextEditingController controller;
  final bool codigo;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          keyboardType: TextInputType.multiline,
          style: TextStyle(fontFamily: codigo ? 'monospace' : null, fontSize: codigo ? 13 : 15, height: 1.5),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
      );
}
