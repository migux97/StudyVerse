import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/supabase_chat_repository.dart';
import '../domain/mensaje.dart';

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => SupabaseChatRepository(ref.watch(supabaseClientProvider)),
);

/// Estado del chat abierto: los mensajes cargados (del más viejo al más
/// nuevo), si hay más para atrás y hasta dónde había leído al entrar.
class EstadoChat {
  const EstadoChat({
    this.mensajes = const [],
    this.cargando = true,
    this.hayMas = true,
    this.cargandoMas = false,
    this.leidoAlEntrar,
    this.error,
  });

  final List<Mensaje> mensajes;
  final bool cargando;
  final bool hayMas;
  final bool cargandoMas;

  /// Para la marca de "Mensajes nuevos" (no se mueve mientras está abierto).
  final DateTime? leidoAlEntrar;
  final String? error;

  EstadoChat copyWith({
    List<Mensaje>? mensajes,
    bool? cargando,
    bool? hayMas,
    bool? cargandoMas,
    DateTime? leidoAlEntrar,
    String? error,
    bool sinError = false,
  }) =>
      EstadoChat(
        mensajes: mensajes ?? this.mensajes,
        cargando: cargando ?? this.cargando,
        hayMas: hayMas ?? this.hayMas,
        cargandoMas: cargandoMas ?? this.cargandoMas,
        leidoAlEntrar: leidoAlEntrar ?? this.leidoAlEntrar,
        error: sinError ? null : (error ?? this.error),
      );
}

const _pagina = 50;

class ChatController extends Notifier<EstadoChat> {
  ChatController(this.groupId);
  final String groupId;

  ChatRepository get _repo => ref.read(chatRepositoryProvider);

  @override
  EstadoChat build() {
    // Un solo canal en vivo por grupo (lo comparte con el número de sin leer).
    ref.listen(chatEventosProvider(groupId), (_, e) {
      if (e.value case (final String id, _)) _alCambiar(id);
    });
    Future.microtask(_cargar);
    return const EstadoChat();
  }

  Future<void> _cargar() async {
    try {
      final (leido, pagina) = await (_repo.leidoHasta(groupId), _repo.pagina(groupId, limite: _pagina)).wait;
      if (!ref.mounted) return;
      // Los que llegaron en vivo mientras cargaba y no vinieron en la página.
      final ids = {for (final m in pagina) m.id};
      final vivos = state.mensajes.where((m) => !ids.contains(m.id));
      state = state.copyWith(
        mensajes: [...pagina.reversed, ...vivos]..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
        cargando: false,
        hayMas: pagina.length == _pagina,
        leidoAlEntrar: leido ?? DateTime.fromMillisecondsSinceEpoch(0),
        sinError: true,
      );
      await marcarLeido();
    } on ParallelWaitError<dynamic, dynamic> catch (e) {
      if (ref.mounted) state = state.copyWith(cargando: false, error: _mensajeDe(e.errors));
    } on ChatFailure catch (e) {
      if (ref.mounted) state = state.copyWith(cargando: false, error: e.mensaje);
    }
  }

  String _mensajeDe(Object errores) {
    final lista = errores is (Object?, Object?) ? [errores.$1, errores.$2] : const [];
    return lista.whereType<ChatFailure>().firstOrNull?.mensaje ?? 'Algo salió mal. Probá de nuevo';
  }

  Future<void> reintentar() async {
    state = const EstadoChat();
    await _cargar();
  }

  /// Los 50 anteriores (al llegar arriba de todo).
  Future<void> cargarMas() async {
    if (!state.hayMas || state.cargandoMas || state.mensajes.isEmpty) return;
    state = state.copyWith(cargandoMas: true);
    try {
      final pagina = await _repo.pagina(groupId, antesDe: state.mensajes.first.createdAt, limite: _pagina);
      if (!ref.mounted) return;
      final ids = {for (final m in state.mensajes) m.id};
      state = state.copyWith(
        mensajes: [...pagina.reversed.where((m) => !ids.contains(m.id)), ...state.mensajes],
        hayMas: pagina.length == _pagina,
        cargandoMas: false,
      );
    } on ChatFailure {
      if (ref.mounted) state = state.copyWith(cargandoMas: false);
    }
  }

  /// Llegó (o cambió) un mensaje: se lee y se pone en su lugar.
  Future<void> _alCambiar(String id) async {
    try {
      final m = await _repo.mensaje(id);
      if (m != null && ref.mounted) await poner(m);
    } on ChatFailure {
      // Se vuelve a leer al reabrir.
    }
  }

  /// Pone [m] en la lista (o lo reemplaza si ya estaba).
  Future<void> poner(Mensaje m) async {
    final lista = [...state.mensajes];
    final i = lista.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      lista[i] = m;
    } else {
      // Uno viejo que no está cargado (lo editaron o borraron): aparece al
      // paginar; agregarlo ahora haría que la paginación saltee los del medio.
      if (state.hayMas && lista.isNotEmpty && m.createdAt.isBefore(lista.first.createdAt)) return;
      lista
        ..add(m)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    state = state.copyWith(mensajes: lista);
    if (i < 0 && !state.cargando) await marcarLeido();
  }

  Future<void> marcarLeido() async {
    try {
      await _repo.marcarLeido(groupId);
      if (ref.mounted) ref.invalidate(chatSinLeerProvider);
    } on ChatFailure {
      // No es grave: queda como no leído.
    }
  }
}

final chatProvider =
    NotifierProvider.autoDispose.family<ChatController, EstadoChat, String>(ChatController.new);

/// Sin leer por grupo (para el número en la pestaña Chat).
final chatSinLeerProvider = FutureProvider.autoDispose<Map<String, int>>((ref) {
  if (ref.watch(authStateProvider).value == null) return const {};
  return ref.watch(chatRepositoryProvider).sinLeer();
});

/// Mensajes nuevos o cambiados de un grupo, en vivo: (id, contador). El
/// contador hace que Riverpod avise aunque llegue dos veces el mismo id.
final chatEventosProvider = StreamProvider.autoDispose.family<(String, int), String>((ref, groupId) {
  var n = 0;
  return ref.watch(chatRepositoryProvider).cambios(groupId).map((id) => (id, ++n));
});

/// Cuántos sin leer tiene el chat de [groupId].
final sinLeerDelGrupoProvider = Provider.autoDispose.family<int, String>((ref, groupId) {
  ref.listen(chatEventosProvider(groupId), (_, _) => ref.invalidate(chatSinLeerProvider));
  return ref.watch(chatSinLeerProvider).value?[groupId] ?? 0;
});
