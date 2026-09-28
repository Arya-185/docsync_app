# DocSync AI (Flutter)

An Android app that connects to the DocSync backend and provides **Ask AI**
(chat + voice) over **document search**, with file downloads. Built feature-wise
in an MVC layout with **Riverpod** for state management.

## Features
- **Login** — Email → Password → Company code. The backend URL is fixed
  (`ak.aryamehta.com`) and never shown. The `PHPSESSID` session cookie is
  persisted, so you stay signed in across restarts.
- **Ask AI** tab — streamed answers (SSE from `/app/rag_answer.php`) with tappable
  source chips. "New chat" starts a fresh thread.
- **Search** tab — document search (`/app/rag_search.php`). Results are
  **consolidated** (repeated chunks of the same file merged into one), ranked by
  relevance, and capped to the **top 5**.
- **Client identity** — each result shows **"client name - firm name"**
  (`contact_person - firm_name`) instead of a client number, resolved via the
  backend endpoint `app/rag_clients.php`.
- **Download** — tapping any result/source opens a sheet with file details and a
  **Download** button (streams the file via the DocSync staff proxy), then **Open**.
- **Voice input** — mic button uses on-device speech-to-text to fill the query
  (no cloud STT, no text-to-speech).
- The launcher icon and login logo are the DocSync logo.

## Architecture (feature-wise MVC + Riverpod)
```
lib/
  core/            config, theme, network/ApiClient, Riverpod root providers
  shared/          models (Citation, DocFile, util), consolidate, services (voice), widgets
  features/
    auth/          model (repository) · controller (AuthController) · view (LoginScreen)
    chat/          model (repository, models) · controller (ChatController) · view
    search/        model (repository, models) · controller (SearchController) · view
    clients/       model (ClientInfo, repository) · controller (ClientDirectory cache)
    files/         model (DownloadRepository) · controller (DownloadController) · view (sheet)
    home/          view (HomeScreen shell with tabs)
```
- **Model**: data classes + repositories (all HTTP lives here, via `ApiClient`).
- **Controller**: Riverpod `Notifier`s holding immutable state.
- **View**: `ConsumerWidget`/`ConsumerStatefulWidget` screens and widgets.

## Backend endpoints used
| Purpose | Endpoint | Method |
|---|---|---|
| Login | `/login.php` (`email`,`password`,`cmp_abbr`,`submit`) | POST (form) |
| Ask AI (SSE) | `/app/rag_answer.php` (`query`,`k`,`conv`) | POST (form) |
| Search (JSON) | `/app/rag_search.php` (`query`,`k`) | POST (form) |
| History | `/app/rag_conversations.php?action=list` / `&action=messages&c=<id>` | GET |
| Client names | `/app/rag_clients.php?ids=1,2,3` → `[{id,contact_person,firm_name}]` | GET |
| Download (2-step) | `/app/client_files.php?client_id=<id>` then `/app/client_files_action.php?action=download&p=<rel>` | GET |

All require a valid DocSync session (and the per-company `ai_search` feature for RAG).

> **Backend note:** `app/rag_clients.php` is a **new** endpoint added to the DocSync
> repo. It must be deployed to `ak.aryamehta.com` (push to `arya`) for client
> names to resolve; until then the app falls back to `Client #<id>`.

## Download behaviour
Downloads use **`background_downloader`**, which shows a **sticky progress
notification with a percentage** while running, then the finished file is moved
into the phone's **public Downloads folder** (`moveToSharedStorage`). Progress is
also shown in the sheet. A completed file can be **downloaded again** from the
sheet. Because the download endpoint reads the client id from the shared PHP
session (`cf_client_id`), `DownloadRepository` first sets it (in-app GET) then
runs the task carrying the session cookie, and **serializes** the whole
set→download under an async lock to avoid cross-client races.

## Run
```
flutter pub get
dart run flutter_launcher_icons   # (re)generate launcher icons if the logo changes
flutter run                       # pick an Android device/emulator
flutter build apk
```

## Notes
- `android/app/build.gradle.kts` pins `compileSdk = 36` / `minSdk = 24`. Mic
  permission is handled by `speech_to_text`; `RECORD_AUDIO` is declared in the manifest.
