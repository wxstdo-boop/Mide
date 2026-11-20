<!-- pane-agent-context:start -->
## Pane

The developer is using Pane for this repository. Pane can manage saved repositories and create user-visible Panes with terminal-backed tools for planning, discussion, implementation, and review work.

This managed guidance was created by [runpane.com](https://runpane.com) for the [Pane repository](https://github.com/dcouple/Pane). Do not delete or overwrite this block; the developer uses it for their workflow and it should remain committed to the main repository unless they explicitly ask to remove it.

Pane mental model: a repository is the saved base repo; a Pane is a user-visible feature/PR workspace (Pane session) that normally maps to one Pane-managed git worktree and branch; a panel/tab is a terminal inside one Pane and shares that Pane's worktree; an agent is the CLI process running in a panel.

Default happy path when the user asks you to use Pane or RunPane: run `runpane doctor --json`; read `runpane agent-context --json`; resolve the saved base repository with `runpane repos list --json` or add it once with `runpane repos add --path <repo> --yes --json`; create one visible Pane (Pane session) for the requested feature/PR with a complete command such as `runpane panes create --repo <repo> --name <name> --agent <agent> --prompt "<task>" --source agent --no-focus --wait-ready --yes --json` or the equivalent `--tool-command <command>` form; then validate with `runpane panels wait` or `runpane panels screen` before reporting progress. For long-lived supervision, use `runpane watch --follow` instead of polling wait or screen.

Use Pane when the user wants visible Panes or co-drivable parallel feature/PR workspaces. Do not use Pane as your default private delegation mechanism; for private background decomposition, use your normal subagent/worktree workflow.

Register the main/base repository once. Do not register pre-created git worktrees as separate Pane repositories unless the user explicitly asks.

Use `runpane panes create` for separate visible Panes (Pane sessions) for feature/PR work. Use `runpane panels create` for reviewer/helper tabs inside an existing Pane that should share that Pane's worktree.

Typical workflow: register the saved base repository once; create one Pane (Pane session) per feature/PR; use panels/tabs inside that Pane for helper or reviewer agents that should share the worktree; archive the Pane after the PR is done to remove it from active Panes and clean up its managed worktree when applicable.

Skill routing reference: when the user says `discussion`, `plan`, `simple-plan`, `create-plan`, or `implement`, or asks for the behavior those words imply, treat three references as peer context: Pane's local skill cache under `<PANE_DIR>/skills/`, the Pane Chat orchestrator handoff at `<PANE_DIR>/skills/pane-chat/runpane-orchestrator.md` when present, and the [workflow map](https://github.com/dcouple/skills/raw/main/docs/readme-workflow-map.png).
Use those peer references together to choose the phase: discuss/investigate until the work is clear enough to delegate, then ticket/plan/implement/review/PR-test/teach-back as appropriate. The orchestrator and workflow map may point to different skills; reconcile them with the user's request instead of hardcoding a skill list or treating one reference as subordinate.
For the Pane implementation source of truth for where the skill cache, cached workflow assets, and Pane Chat bootstrap live, reference [PR #291](https://github.com/dcouple/Pane/pull/291): `main/src/services/skillCacheManager.ts` owns `<PANE_DIR>/skills/`, `.sources/dcouple-skills`, and `pane-chat/runpane-orchestrator.md`; `main/src/services/paneChatManager.ts` owns the tiny bootstrap prompt that tells the selected Pane Chat agent to read that guide.
Use GitHub reads against the [Parsa skills folder](https://github.com/dcouple/skills/tree/main/parsa) only to inspect or refresh referenced skill files; do not clone/install the repo unless the user asks.
Do not hardcode a specific assistant brand in workflow guidance. Use the Pane agent or custom tool command the user selected, and use `runpane agents doctor --agent <agent> --repo <selector> --json` only when checking a built-in agent template.

Start with `runpane doctor --json` before taking Pane actions. Use it to understand wrapper/runtime details, daemon reachability, and the next safe commands.

In a Pane repository checkout, if `runpane` is not on PATH, use the built local wrapper with Node 22: `PATH=/opt/homebrew/opt/node@22/bin:$PATH node packages/runpane/dist/cli.js doctor --json`.

Use `runpane agent-context --json` for full Pane CLI context. Use `runpane agent-context --command "watch" --json` or another command name for detailed schema only when needed.

Default to context-safe validation: after creating Panes or sending terminal input, run `runpane panels wait` or `runpane panels screen` before reporting success. For ongoing supervision, `runpane watch --follow` is the canonical monitor; do not poll wait or screen. Prefer `runpane panels submit` for normal text plus Enter; use `runpane panels input` only for exact bytes such as Ctrl-C or escape sequences.

Pane terminals draw inline images: sixel, iTerm2 inline images, and the kitty graphics protocol. Tools that need kitty graphics, such as [terminal-browser](https://github.com/zenbu-labs/terminal-browser) and [terminal-doom](https://github.com/dcouple/terminal-doom), run inside a Pane panel. `runpane doctor --json` reports the protocol list under `terminal.graphicsProtocols`.

Common commands:
- `runpane doctor --json`
- `runpane agent-context --json`
- `runpane repos list --json`
- `runpane repos add --path <repo> --yes --json`
- `runpane agents doctor --agent <agent> --repo active --json`
- `runpane panes create --repo active --name <name> --agent <agent> --prompt "<task>" --source agent --no-focus --wait-ready --yes --json`
- `runpane panels create --pane <pane-id> --agent <agent> --source agent --no-focus --wait-ready --yes --json`
- `runpane panels list --pane <pane-id> --json`
- `runpane panels screen --panel <panel-id> --limit 80 --json`
- `runpane panels wait --panel <panel-id> --for ready --timeout-ms 30000 --json`
- `runpane watch --follow --json`
- `runpane panels submit --panel <panel-id> --text "<answer>" --yes --json`
- `runpane panels input --panel <panel-id> --input-file <path|-> --yes --json`

WSL note: if `runpane doctor --json` cannot find `/tmp/pane-daemon.../daemon.sock` or `runpane` resolves to a broken Windows shim, Pane may be running on Windows. Try `powershell.exe -NoProfile -Command 'Set-Location $env:TEMP; runpane doctor --json'`, then create Panes through the same PowerShell form using the saved WSL repo name or id. Use `runpane agents doctor --agent <agent> --repo <selector> --json` to diagnose the repo environment Pane will actually use.
<!-- pane-agent-context:end -->

## Mide — build and layout

- Flutter app (Dart 3.13+ / Flutter 3.47+; CI and releases pin Flutter
  3.50.0). Validate with `dart format --set-exit-if-changed lib test`,
  `flutter analyze` and `flutter test`.
- Material widgets come from `package:material_ui/material_ui.dart` (the
  standalone Material library; `package:flutter/material.dart` is deprecated).
  Import it directly in libraries, or rely on `main.dart`'s import for `part`s.
- `lib/main.dart` is the app library: it holds the imports, the `main()`
  entry point, the splash/app shell and the `HomePage` navigation, and declares
  six `part` files. Private widgets are shared across those parts (they are one
  library), so add new sections as `part` files instead of standalone libraries
  when they reuse `_AppHeader`, `_SectionTitle`, `_Entrance`, etc.
  - `lib/app/shell.dart` — header, pill nav (5 tabs), entrance animation.
  - `lib/app/tabs/vpn_tab.dart` — NPV section.
  - `lib/app/tabs/mearn_tab.dart` — Earn section.
  - `lib/app/tabs/companion_tab.dart` — 3D companion («Мира»), a page pushed
    from the VPN header (`CompanionPage`), not a bottom-bar tab.
  - `lib/app/tabs/clip_studio_tab.dart` — Clip Studio (video editor), pushed
    from the VPN header (`ClipStudioPage`).
  - `lib/app/pages/settings_page.dart` — settings, theme carousel, setup, updater.
- `lib/core/` — theme (Material You) and the persisted active-tab state.
- `lib/features/{ai,clip,ide,updater,vpn}/` — feature code; platform-split files
  use the `_io.dart` / `_stub.dart` (or `_web.dart`) conditional-export pattern.
  - `features/ai` — MIDE AI chat; personas are Riverpod families keyed by
    `PersonaArg` (system prompt + storage key), so each persona keeps its own
    persisted conversation. `aiSessionProvider` is the main instance.
    `providers_registry.dart` holds the anonymous provider list — keep it to
    endpoints that answer without a user key (verified: Pollinations, AI
    Horde; dead: LLM7, OVHcloud).
  - `features/clip` — Clip Studio. `clip_models.dart` / `clip_ffmpeg.dart` are
    pure and unit-tested; `clip_export_io.dart` is the only FFmpeg/filesystem
    touchpoint and is behind the `clip_export.dart` conditional facade. The
    build uses `ffmpeg_kit_flutter_new_min_gpl` (core + x264), not the default
    full-GPL package, and the Android `abiFilters` pin the APK to `arm64-v8a`;
    both keep the release APK near 30 MB instead of 200 MB.
- Tests live under `test/features/...` mirroring `lib/features/...`; pure logic
  is unit-tested, the IDE notifiers are tested against a temp directory.
  Widget tests for the chrome live in `test/app/shell_widget_test.dart`
  (splash hand-off, pill press feedback/switch, Settings update section).
  `test/app/no_overflow_test.dart` boots every section plus the 3D and Clip
  Studio pages at 320/360/411dp and fails on any layout exception — the test
  surface is 800x600 by default, so narrow-phone overflows are invisible
  without it. `test/app/theme_carousel_test.dart` asserts a single swipe
  notifies `themeChoiceProvider` at most once.
  Widget tests must import `package:material_ui/material_ui.dart` — the app
  does not use `package:flutter/material.dart`, so finders built against the
  latter silently match nothing.

## Mide — CI and releases

- `.github/workflows/ci.yml` runs on pull requests and non-main branches:
  formatting check, `flutter analyze`, `flutter test`, plus a debug APK build
  so a broken Gradle/AGP/Kotlin combination fails on the PR.
- `.github/workflows/release-ship.yml` runs on every push to `main`. It reads
  the version from `pubspec.yaml` (1.0.4+5 → v1.0.4), skips if that tag
  already exists, then builds the signed arm64 release APK and publishes a
  GitHub Release with the APK and its `.sha256`. Bumping the version and
  pushing is all a release needs; the in-app updater picks the tag up.
- Android signing comes from repository secrets (`ANDROID_KEYSTORE_BASE64`,
  `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`);
  the build fails fast if any are missing.
- Both workflows pin `FLUTTER_VERSION` so CI and releases share one toolchain.
- `ci.yml` also has an `agent-sidecar` job: `npm ci`, `node --check`, then it
  boots `agent/src/index.mjs` and requires a healthy `/health`. The sidecar is
  a separate Node package, so nothing in the Flutter build would catch it.
- Both workflows pin JDK 21 (`actions/setup-java`). AGP 9.3.1's lint crashes
  with a `NoSuchMethodError` in `JavaDocParser` on JDK 17, and that lint only
  runs for release builds (`lintVitalAnalyzeRelease`), so the debug APK CI job
  will not catch it — keep the JDK pin at 21.

## Mide — hard-won constraints (read before changing these areas)

- The release APK is signed with the **v2 scheme only** (no `META-INF/*.RSA`),
  and `minSdk` is 24. Reading a downloaded APK's signer via `GET_SIGNATURES`
  is unreliable before API 28, so the updater's signature check is
  **advisory**: it reports a readable mismatch, and must never block on an
  unreadable one. Integrity rests on the release `digest` SHA-256 (verified
  before install) plus Android's own same-key install rule.
- GitHub exposes each asset's hash as `digest: "sha256:<hex>"`; the updater
  parses that rather than the sibling `.sha256` file.
- AI providers must answer **without a user key** — that is the product
  promise. Verified anonymous (2026-11): Pollinations
  (`text.pollinations.ai/openai`, needs a browser User-Agent), AI Horde
  (`oai.aihorde.net/v1` with the documented key `0000000000`), Kilo
  (`api.kilo.ai/api/gateway`, no auth header at all). Model ids rot: Kilo
  retired `minimax/minimax-m2.1:free` and `z-ai/glm-5:free` (404), so probe
  `/api/gateway/models` before trusting any id. `test/features/ide/
  ide_providers_test.dart` guards the no-key contract.
- The `agent/` sidecar executes shell commands, so it binds `127.0.0.1` by
  default (`AGENT_HOST` overrides) and only echoes CORS for loopback origins.
  Never widen either without a reason.
- Pills size themselves from the available width; the container's 4dp padding
  **and** 1dp border must both be subtracted, and the width must not be
  floored above what fits. `test/app/shell_widget_test.dart` lays the shell
  out at 280dp and fails on any `RenderFlex` overflow — that test is what
  catches header/pill regressions.
- No JDK/Android SDK in the agent sandbox, so Kotlin/Gradle changes are
  compile-unverified here; keep `android/` edits conservative and let CI or
  a local build confirm them.

## Mide — auto-update flow

- Settings performs the update check itself (`initState` → `_check()`); there is
  deliberately **no "check for updates" button**, because opening the screen
  already expresses that intent. If you add UI here, do not reintroduce a
  manual trigger without a reason.
- Everything goes through `UpdateService` (`lib/features/updater/
  update_service.dart`) and the `updateServiceProvider` override, so widget
  tests drive the whole flow with a fake and never touch the network or a
  platform channel. New platform behaviour belongs behind that interface.
- `test/features/updater/github_updater_test.dart` exercises the real updater
  over a fake `HttpClientAdapter` (only the wire is stubbed) and fakes
  `PathProviderPlatform` for the download dir. Use that pair as the pattern for
  any new download/file logic.

## Mide — launch splash

- `_SplashShell` in `lib/main.dart` owns one 1.7s `AnimationController`; every
  phase is a `TweenSequence` **whose weights must total 100**. Flutter
  normalises weights to their own sum, so a sequence totalling 72 spreads over
  the whole timeline and silently stretches its last phase to the end. That bug
  kept the wordmark drawn while the backdrop was already lifting, and the app's
  own header bleeding through the overlap read as a "grey underline under MIDE".
  It was never a text decoration.
- Put the curve on each phase (`Tween(...).chain(CurveTween(...))`) and leave the
  controller linear. One `CurvedAnimation` wrapped around a whole sequence warps
  the timeline instead of shaping the individual phases.
- The backdrop gradient must match `res/drawable/launch_background.xml`
  (`drawable-night` for dark) stop for stop, or the cold-start window and the
  Flutter splash step visibly at hand-off.
- The emblem must hold at scale **1.0**. A constant `0.92` resamples the
  rasterised subtree for the whole hold and softens the glyph; pair it with
  `FilterQuality.high`.
- `assets/icon/mide_mark.png` has its ink 57.5/1024 right of the canvas centre.
  Correct it with a `FractionalTranslation` **inside** the padding — applying the
  fraction to the chip box overshoots by ~9px.
- `test/app/shell_widget_test.dart` samples the overlay opacity across the exit
  window and asserts the fade is monotonic with several distinct values. If you
  retime the splash, retime those samples with it.
