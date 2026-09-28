import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config.dart';
import '../../../core/providers.dart';
import '../../chat/controller/chat_controller.dart';
import '../../clients/controller/client_directory.dart';
import '../../search/controller/search_controller.dart';
import '../model/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);

/// Immutable auth screen/session state.
class AuthState {
  final bool authenticated;
  final bool loading;
  final String? error;
  final String cmpAbbr;
  final String email;

  const AuthState({
    this.authenticated = false,
    this.loading = false,
    this.error,
    this.cmpAbbr = '',
    this.email = '',
  });

  AuthState copyWith({
    bool? authenticated,
    bool? loading,
    String? error,
    bool clearError = false,
    String? cmpAbbr,
    String? email,
  }) {
    return AuthState(
      authenticated: authenticated ?? this.authenticated,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      cmpAbbr: cmpAbbr ?? this.cmpAbbr,
      email: email ?? this.email,
    );
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return AuthState(
      cmpAbbr: prefs.getString(AppConfig.prefCmpAbbr) ?? '',
      email: prefs.getString(AppConfig.prefEmail) ?? '',
    );
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  /// On startup: if a persisted session cookie is still live, go straight in.
  Future<void> restore() async {
    final ok = await _repo.verifySession();
    if (ok) state = state.copyWith(authenticated: true);
  }

  Future<void> login({
    required String email,
    required String password,
    required String cmpAbbr,
  }) async {
    state = state.copyWith(loading: true, clearError: true);

    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(AppConfig.prefEmail, email.trim());
    await prefs.setString(AppConfig.prefCmpAbbr, cmpAbbr.trim());

    final outcome = await _repo.login(
      email: email.trim(),
      password: password,
      cmpAbbr: cmpAbbr.trim(),
    );

    // A fresh sign-in must never inherit the previous account's in-memory state
    // (chat transcript, conversation, cached client names, search results).
    if (outcome.success) _resetUserScopedState();

    state = state.copyWith(
      loading: false,
      authenticated: outcome.success,
      error: outcome.error,
      email: email.trim(),
      cmpAbbr: cmpAbbr.trim(),
    );
  }

  Future<void> logout() async {
    await _repo.logout();
    // Wipe every per-user provider so the next account starts clean — the chat
    // controllers etc. are plain (non-autoDispose) Notifiers and would otherwise
    // survive logout and prefill the next login with the previous user's data.
    _resetUserScopedState();
    state = state.copyWith(authenticated: false, clearError: true);
  }

  /// Reset all user-scoped in-memory state to its initial value. Cheap: an
  /// invalidated provider only rebuilds if something is currently watching it.
  void _resetUserScopedState() {
    // Drop a turn still streaming for the previous account before its controller goes away.
    ref.read(chatControllerProvider.notifier).cancelActive();
    ref.invalidate(chatControllerProvider);
    ref.invalidate(chatHistoryProvider);
    ref.invalidate(clientDirectoryProvider);
    ref.invalidate(searchControllerProvider);
  }
}
