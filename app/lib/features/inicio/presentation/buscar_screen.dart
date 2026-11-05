import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/pagina.dart';
import '../../files/domain/file_item.dart';
import '../../files/presentation/file_icon.dart';
import '../../files/presentation/files_providers.dart';

/// "Buscar en StudyVerse": archivos de todos tus grupos, por nombre.
class BuscarScreen extends ConsumerStatefulWidget {
  const BuscarScreen({super.key});

  @override
  ConsumerState<BuscarScreen> createState() => _BuscarScreenState();
}

class _BuscarScreenState extends ConsumerState<BuscarScreen> {
  final _texto = TextEditingController();
  Timer? _espera;
  String _buscado = '';

  @override
  void dispose() {
    _espera?.cancel();
    _texto.dispose();
    super.dispose();
  }

  void _alEscribir(String t) {
    _espera?.cancel();
    setState(() {}); // Muestra u oculta la X al instante.
    // Espera a que se deje de escribir un momento antes de buscar.
    _espera = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _buscado = t.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resultados = ref.watch(busquedaProvider(_buscado));
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.grupos)),
        titleSpacing: 0,
        title: TextField(
          controller: _texto,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _alEscribir,
          onSubmitted: (t) {
            _espera?.cancel();
            setState(() => _buscado = t.trim());
          },
          decoration: InputDecoration(
            hintText: 'Buscar en StudyVerse',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            suffixIcon: _texto.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Borrar',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _espera?.cancel();
                      setState(() {
                        _texto.clear();
                        _buscado = '';
                      });
                    },
                  ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: _buscado.length < 2
              ? SinVista(
                  icono: Icons.search,
                  motivo: 'Buscá archivos de todos tus grupos por su nombre.\nNo importan las tildes ni las mayúsculas.',
                )
              : resultados.when(
                  skipLoadingOnReload: true,
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const SinVista(motivo: 'No pudimos buscar. Revisá tu conexión.'),
                  data: (r) => r.isEmpty
                      ? SinVista(icono: Icons.search_off, motivo: 'No encontramos nada con «$_buscado».')
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: r.length,
                          separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                          itemBuilder: (_, i) {
                            final x = r[i];
                            return ListTile(
                              leading: FileIcon(kind: x.kind),
                              title: Text(x.visible, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                '${x.ubicacion} · ${formatearFecha(x.actualizado, DateTime.now())}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: scheme.onSurfaceVariant),
                              ),
                              onTap: () => context.push(x.kind == FileKind.studyverse
                                  ? Routes.documento(x.groupId, x.fileId)
                                  : Routes.archivo(x.groupId, x.fileId)),
                            );
                          },
                        ),
                ),
        ),
      ),
    );
  }
}
