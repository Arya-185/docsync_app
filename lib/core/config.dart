/// App-wide configuration and persisted-preference keys.
class AppConfig {
  /// DocSync backend. Fixed — not shown or editable in the UI.
  /// The tanisha server (branch `tanisha`) since 5 Oct 2026, now that it runs the same code as
  /// ak (branch `arya`, 'https://ak.aryamehta.com'), which was the default from 2 to 5 Oct.
  static const String defaultBaseUrl =
      'https://pragmainfotech.com/docsyncin_test';

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
