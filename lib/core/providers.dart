import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'network/api_client.dart';

/// Core singletons. Both are created asynchronously in `main()` and injected
/// via `ProviderScope(overrides: [...])`, so the bodies here are never called.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

final apiClientProvider = Provider<ApiClient>(
  (ref) => throw UnimplementedError('apiClientProvider must be overridden'),
);
