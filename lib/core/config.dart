/// App-wide configuration and persisted-preference keys.
class AppConfig {
  /// DocSync backend. Fixed — not shown or editable in the UI.
  /// ak (branch `arya`) since 2 Oct 2026, where the new Ask AI features deploy first. The
  /// previous server was 'https://pragmainfotech.com/docsyncin_test'; switch back once it runs
  /// the same code (it has no open.php / ai_preview.php / ai_fix.php yet).
  static const String defaultBaseUrl = 'https://ak.aryamehta.com';

  // shared_preferences keys.
  static const String prefCmpAbbr = 'cmp_abbr';
  static const String prefEmail = 'email';

  /// Backend timeouts (mirror rag_bridge.php: RAG_TIMEOUT 60s, RAG_ANSWER_TIMEOUT 150s).
  static const Duration searchTimeout = Duration(seconds: 65);
  static const Duration answerTimeout = Duration(seconds: 160);
  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration downloadTimeout = Duration(seconds: 180);

  /// Default retrieval count sent to the backend.
  static const int defaultK = 10;

  /// Max results shown after consolidation.
  static const int maxResults = 5;
}
