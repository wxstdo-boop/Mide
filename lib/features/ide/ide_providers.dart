// PC-only IDE core: workspace tree, open file tabs, console runner and
// interpreter tool paths. Everything here touches dart:io, so it is only
// reachable from ide_screen.dart (which is itself behind the desktop gate).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ── Workspace (opened project folder) ──────────────────────────────────────

/// One node of the workspace tree (file or directory).
class IdeFsNode {
  final String name;
  final String path;
  final bool isDir;

  const IdeFsNode({required this.name, required this.path, required this.isDir});
}

/// Directories never shown in the tree — build noise, not user code.
const Set<String> _ideHiddenDirs = {
  '.git',
  '.dart_tool',
  'build',
  'node_modules',
  '.idea',
};

/// Basename helper that works for both `\` (Windows) and `/` paths.
String ideBaseName(String path) {
  final norm = path.replaceAll('\\', '/');
  final i = norm.lastIndexOf('/');
  return i < 0 ? path : path.substring(i + 1);
}

/// Parent directory helper for both separators.
String ideParentOf(String path) {
  final norm = path.replaceAll('\\', '/');
  final i = norm.lastIndexOf('/');
  if (i <= 0) return path;
  // Keep "C:/" roots intact.
  return path.substring(0, i);
}

String _ideExt(String path) {
  final name = ideBaseName(path);
  final i = name.lastIndexOf('.');
  return i <= 0 ? '' : name.substring(i).toLowerCase();
}

class IdeWorkspaceState {
  /// Absolute path of the opened project root (null before opening).
  final String? root;

  /// dir path -> lazily loaded children.
  final Map<String, List<IdeFsNode>> children;

  /// Expanded directory paths.
  final Set<String> expanded;

  /// Currently selected node path.
  final String? selected;

  final bool loading;
  final String? error;

  const IdeWorkspaceState({
    this.root,
    this.children = const {},
    this.expanded = const {},
    this.selected,
    this.loading = false,
    this.error,
  });

  bool get isOpen => root != null;

  IdeWorkspaceState copyWith({
    String? root,
    bool clearRoot = false,
    Map<String, List<IdeFsNode>>? children,
    Set<String>? expanded,
    String? selected,
    bool clearSelected = false,
    bool? loading,
    String? error,
    bool clearError = false,
  }) =>
      IdeWorkspaceState(
        root: clearRoot ? null : (root ?? this.root),
        children: children ?? this.children,
        expanded: expanded ?? this.expanded,
        selected: clearSelected ? null : (selected ?? this.selected),
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

class IdeWorkspaceNotifier extends Notifier<IdeWorkspaceState> {
  @override
  IdeWorkspaceState build() => const IdeWorkspaceState();

  /// Reads a directory synchronously (fast for normal project sizes),
  /// hiding build noise and sorting folders before files.
  List<IdeFsNode> _readDir(String path) {
    final out = <IdeFsNode>[];
    try {
      for (final e in Directory(path).listSync(followLinks: false)) {
        final name = ideBaseName(e.path);
        if (_ideHiddenDirs.contains(name)) continue;
        if (e is Directory) {
          out.add(IdeFsNode(name: name, path: e.path, isDir: true));
        } else if (e is File) {
          out.add(IdeFsNode(name: name, path: e.path, isDir: false));
        }
      }
    } catch (_) {
      // Unreadable dir (permissions) — show as empty.
    }
    out.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  void _reloadDir(String path) {
    final children = Map<String, List<IdeFsNode>>.from(state.children);
    children[path] = _readDir(path);
    state = state.copyWith(children: children);
  }

  /// Opens [raw] as the project root. Returns null on success or an
  /// error message to show in a dialog/snackbar.
  String? openFolder(String raw) {
    var p = raw.trim().replaceAll('"', '');
    if (p.isEmpty) return 'Путь пустой';
    // Accept pasted forward-slash paths on Windows.
    if (Platform.isWindows && p.contains('/') && !p.contains('\\')) {
      p = p.replaceAll('/', '\\');
    }
    final dir = Directory(p);
    if (!dir.existsSync()) return 'Папка не найдена: $p';

    final children = <String, List<IdeFsNode>>{};
    final rootPath = dir.path;
    children[rootPath] = _readDir(rootPath);
    state = IdeWorkspaceState(
      root: rootPath,
      children: children,
      expanded: {rootPath},
    );
    return null;
  }

  void closeFolder() => state = const IdeWorkspaceState();

  void select(String? path) => state = state.copyWith(
        selected: path ?? '',
        clearSelected: path == null,
        clearError: true,
      );

  /// Toggles (or forces) expansion of a directory; first expand loads it.
  void toggle(String path, {bool? expand}) {
    final expanded = Set<String>.from(state.expanded);
    final willOpen = expand ?? !expanded.contains(path);
    if (willOpen) {
      expanded.add(path);
      if (!state.children.containsKey(path)) {
        final children = Map<String, List<IdeFsNode>>.from(state.children);
        children[path] = _readDir(path);
        state =
            state.copyWith(expanded: expanded, children: children, clearError: true);
        return;
      }
    } else {
      expanded.remove(path);
    }
    state = state.copyWith(expanded: expanded, clearError: true);
  }

  /// Re-reads the root and every expanded directory from disk.
  void refresh() {
    final root = state.root;
    if (root == null) return;
    final children = <String, List<IdeFsNode>>{};
    for (final p in {root, ...state.expanded}) {
      children[p] = _readDir(p);
    }
    state = state.copyWith(children: children, clearError: true);
  }

  /// Creates a file or folder inside [parentPath]. Returns null on success
  /// or an error message. On success for a file, returns nothing — callers
  /// use [createdPath] for the just-created node.
  String? createdPath;

  String? createEntry({
    required String parentPath,
    required bool asDir,
    required String name,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Имя пустое';
    if (trimmed.contains('/') || trimmed.contains('\\')) {
      return 'Имя не может содержать "/" или "\\"';
    }
    final sep = Platform.pathSeparator;
    final full = parentPath.endsWith('\\') || parentPath.endsWith('/')
        ? '$parentPath$trimmed'
        : '$parentPath$sep$trimmed';
    final asDirectory = Directory(full);
    final asFile = File(full);
    if (asDirectory.existsSync() || asFile.existsSync()) {
      return 'Уже существует: $trimmed';
    }
    try {
      if (asDir) {
        asDirectory.createSync(recursive: false);
      } else {
        asFile.writeAsStringSync('');
      }
    } catch (e) {
      return 'Не удалось создать: $e';
    }
    createdPath = full;
    toggle(parentPath, expand: true);
    _reloadDir(parentPath);
    state = state.copyWith(selected: full);
    return null;
  }

  /// Renames/moves [path] to [newName] inside the same directory.
  /// Returns null on success or an error message.
  String? rename(String path, String newName) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return 'Имя пустое';
    if (trimmed.contains('/') || trimmed.contains('\\')) {
      return 'Имя не может содержать "/" или "\\"';
    }
    final parent = ideParentOf(path);
    final target = '$parent${Platform.pathSeparator}$trimmed';
    if (target == path) return null;
    if (File(target).existsSync() || Directory(target).existsSync()) {
      return 'Уже существует: $trimmed';
    }
    try {
      if (Directory(path).existsSync()) {
        Directory(path).renameSync(target);
      } else {
        File(path).renameSync(target);
      }
    } catch (e) {
      return 'Не удалось переименовать: $e';
    }
    createdPath = target;
    _reloadDir(parent);
    state = state.copyWith(selected: target);
    return null;
  }

  /// Deletes a file or (recursive) directory. Returns null on success.
  String? delete(String path) {
    try {
      if (Directory(path).existsSync()) {
        Directory(path).deleteSync(recursive: true);
      } else if (File(path).existsSync()) {
        File(path).deleteSync();
      } else {
        return 'Уже не существует';
      }
    } catch (e) {
      return 'Не удалось удалить: $e';
    }
    // Drop the node and every cached child of a removed directory.
    final children = Map<String, List<IdeFsNode>>.from(state.children)
      ..removeWhere((k, _) => k == path || k.startsWith('$path\\') || k.startsWith('$path/'));
    final expanded = Set<String>.from(state.expanded)
      ..removeWhere((p) => p == path || p.startsWith('$path\\') || p.startsWith('$path/'));
    state = state.copyWith(children: children, expanded: expanded, clearSelected: true);
    _reloadDir(ideParentOf(path));
    return null;
  }
}

// ── Open file tabs ─────────────────────────────────────────────────────────

/// One editor tab: the file buffer plus the last saved snapshot (dirty flag).
class IdeTab {
  final String path;
  final String name;

  /// Current buffer.
  final String content;

  /// Content as it was loaded from / saved to disk.
  final String saved;

  const IdeTab({
    required this.path,
    required this.name,
    required this.content,
    required this.saved,
  });

  bool get dirty => content != saved;

  IdeTab copyWith({String? content, String? saved}) => IdeTab(
        path: path,
        name: name,
        content: content ?? this.content,
        saved: saved ?? this.saved,
      );
}

class IdeTabsState {
  final List<IdeTab> tabs;
  final int active;

  const IdeTabsState({this.tabs = const [], this.active = 0});

  IdeTab? get activeTab => tabs.isEmpty ? null : tabs[active.clamp(0, tabs.length - 1)];

  int indexOfPath(String path) => tabs.indexWhere((t) => t.path == path);

  IdeTabsState copyWith({List<IdeTab>? tabs, int? active}) => IdeTabsState(
        tabs: tabs ?? this.tabs,
        active: active ?? this.active,
      );
}

// ── Tabs notifier ──────────────────────────────────────────────────────────

class IdeTabsNotifier extends Notifier<IdeTabsState> {
  @override
  IdeTabsState build() => const IdeTabsState();

  /// Opens [path] (or activates the tab if already open). Returns an error
  /// message on failure, null on success.
  Future<String?> openFile(String path) async {
    final i = state.indexOfPath(path);
    if (i >= 0) {
      state = state.copyWith(active: i);
      return null;
    }
    String content;
    try {
      final bytes = await File(path).readAsBytes();
      if (bytes.contains(0)) return 'Бинарный файл не открывается: $path';
      content = utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      return 'Не удалось открыть: $e';
    }
    final tab = IdeTab(
      path: path,
      name: ideBaseName(path),
      content: content,
      saved: content,
    );
    state = IdeTabsState(tabs: [...state.tabs, tab], active: state.tabs.length);
    return null;
  }

  void activate(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    state = state.copyWith(active: index);
  }

  /// Closes tab [index]; the neighbour becomes active.
  void close(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    final tabs = [...state.tabs]..removeAt(index);
    var active = state.active;
    if (index < active) {
      active -= 1;
    } else if (active >= tabs.length) {
      active = tabs.length - 1;
    }
    state = IdeTabsState(tabs: tabs, active: active < 0 ? 0 : active);
  }

  void closePath(String path) {
    final i = state.indexOfPath(path);
    if (i >= 0) close(i);
  }

  /// Updates the buffer of [path] (editor keystrokes / AI apply).
  void setContent(String path, String text, {bool markSaved = false}) {
    final i = state.indexOfPath(path);
    if (i < 0) return;
    final tabs = [...state.tabs];
    tabs[i] = tabs[i].copyWith(
      content: text,
      saved: markSaved ? text : null,
    );
    state = state.copyWith(tabs: tabs);
  }

  /// Writes the buffer to disk. [path] defaults to the active tab.
  Future<String?> save({String? path}) async {
    final target = path ?? state.activeTab?.path;
    if (target == null) return 'Нет открытого файла';
    final i = state.indexOfPath(target);
    if (i < 0) return 'Файл не открыт';
    try {
      await File(target).writeAsString(state.tabs[i].content);
    } catch (e) {
      return 'Не удалось сохранить: $e';
    }
    final tabs = [...state.tabs];
    tabs[i] = tabs[i].copyWith(saved: tabs[i].content);
    state = state.copyWith(tabs: tabs);
    return null;
  }

  /// Saves every dirty tab. Returns an error message or null.
  Future<String?> saveAll() async {
    for (final tab in state.tabs.where((t) => t.dirty)) {
      final err = await save(path: tab.path);
      if (err != null) return err;
    }
    return null;
  }

  /// True when at least one buffer differs from disk.
  bool get hasDirty => state.tabs.any((t) => t.dirty);
}

// ── Console runner ─────────────────────────────────────────────────────────

class IdeConsoleState {
  final List<String> lines;
  final bool running;
  final String? runningPath;

  const IdeConsoleState({
    this.lines = const [],
    this.running = false,
    this.runningPath,
  });

  IdeConsoleState copyWith({
    List<String>? lines,
    bool? running,
    String? runningPath,
    bool clearRunningPath = false,
  }) =>
      IdeConsoleState(
        lines: lines ?? this.lines,
        running: running ?? this.running,
        runningPath: clearRunningPath ? null : (runningPath ?? this.runningPath),
      );
}

/// Executable + args attempt for one runner candidate.
class _RunAttempt {
  final String exec;
  final List<String> args;
  const _RunAttempt(this.exec, this.args);
}

/// Run plan for a file extension (several attempts, tried in order).
class _RunPlan {
  final String label;
  final List<_RunAttempt> attempts;
  const _RunPlan(this.label, this.attempts);
}

class IdeConsoleNotifier extends Notifier<IdeConsoleState> {
  Process? _proc;

  /// Bumped on stop/replace so stale stream callbacks are ignored.
  int _generation = 0;

  @override
  IdeConsoleState build() => const IdeConsoleState();

  void clear() => state = state.copyWith(lines: const []);

  void _append(String line) {
    final lines = [...state.lines, line];
    if (lines.length > 600) lines.removeRange(0, lines.length - 600);
    state = state.copyWith(lines: lines);
  }

  /// Builds the runner plan for [file] or null when unsupported.
  _RunPlan? _planFor(String file, IdeToolsState tools) {
    final ext = _ideExt(file);
    final custom = <String, String?>{
      '.dart': tools.of('dart'),
      '.py': tools.of('python'),
      '.js': tools.of('node'),
      '.mjs': tools.of('node'),
      '.ps1': tools.of('pwsh'),
    }[ext];

    String exe(String name) => custom?.isNotEmpty == true ? custom! : name;

    switch (ext) {
      case '.dart':
        return _RunPlan('dart', [_RunAttempt(exe('dart'), [file])]);
      case '.py':
        final first = exe('python');
        return _RunPlan('python', [
          _RunAttempt(first, [file]),
          if (first != 'py') const _RunAttempt('py', []),
          if (first != 'python3') const _RunAttempt('python3', []),
        ]);
      case '.js':
      case '.mjs':
        return _RunPlan('node', [_RunAttempt(exe('node'), [file])]);
      case '.ps1':
        final pwsh = exe('pwsh');
        final common =
            ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', file];
        return _RunPlan('powershell', [
          _RunAttempt(pwsh, common),
          if (pwsh != 'powershell') const _RunAttempt('powershell', []),
        ]);
      case '.bat':
      case '.cmd':
        return _RunPlan('cmd', [_RunAttempt('cmd', ['/c', file])]);
      case '.sh':
        return _RunPlan('bash', [_RunAttempt('bash', [file])]);
      default:
        return null;
    }
  }

  /// Runs [file] in its own directory, streaming output into the console.
  Future<void> run(String file) async {
    if (state.running) return;
    final plan = _planFor(file, ref.read(ideToolsProvider));
    if (plan == null) {
      _append('[❌] Нет раннера для «${_ideExt(file)}» — работают dart, py, '
          'js, ps1, bat, sh');
      return;
    }

    Process? proc;
    var lastMissing = plan.attempts.first.exec;
    for (final attempt in plan.attempts) {
      try {
        proc = await Process.start(
          attempt.exec,
          attempt.args,
          workingDirectory: ideParentOf(file),
        );
        lastMissing = attempt.exec;
        break;
      } on ProcessException {
        continue;
      }
    }
    if (proc == null) {
      _append('[❌] Не найден «$lastMissing» — добавь в PATH или укажи путь '
          'в ⚙ Инструменты');
      return;
    }

    _proc = proc;
    final gen = ++_generation;
    state = state.copyWith(running: true, runningPath: file);
    _append('[▶] ${plan.attempts.first.exec} '
        '${plan.attempts.first.args.join(' ')}');

    void hook(Stream<List<int>> stream, {bool err = false}) {
      utf8.decoder
          .bind(stream)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (gen != _generation) return;
          _append(err ? '[stderr] $line' : line);
        },
        onError: (_) {},
      );
    }

    hook(proc.stdout);
    hook(proc.stderr, err: true);

    final code = await proc.exitCode;
    if (gen != _generation) return;
    _proc = null;
    _append(code == 0 ? '[✓] Готово (код 0)' : '[❌] Завершено с кодом $code');
    state = state.copyWith(running: false, clearRunningPath: true);
  }

  /// Stops the running process.
  void stop() {
    _generation++;
    try {
      _proc?.kill();
    } catch (_) {
      // Already exited.
    }
    _proc = null;
    _append('[⏹] Остановлено');
    state = state.copyWith(running: false, clearRunningPath: true);
  }
}

// ── Interpreter tool paths (⚙ dialog) ─────────────────────────────────────

class IdeToolsState {
  /// tool key (dart|python|node|pwsh) -> custom executable path.
  final Map<String, String> paths;

  const IdeToolsState({this.paths = const {}});

  /// Non-empty custom path for [tool] or null (fall back to PATH).
  String? of(String tool) {
    final v = paths[tool]?.trim();
    return v == null || v.isEmpty ? null : v;
  }
}

class IdeToolsNotifier extends Notifier<IdeToolsState> {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _key = 'mide_ide_tools_v1';

  @override
  IdeToolsState build() {
    _load();
    return const IdeToolsState();
  }

  Future<void> _load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        state = IdeToolsState(paths: {
          for (final e in decoded.entries)
            if (e.key is String && e.value is String)
              e.key as String: e.value as String,
        });
      }
    } catch (_) {
      // Non-fatal: default to PATH lookups.
    }
  }

  Future<void> set(String tool, String path) async {
    final paths = Map<String, String>.from(state.paths)..[tool] = path.trim();
    state = IdeToolsState(paths: paths);
    try {
      await _storage.write(key: _key, value: jsonEncode(paths));
    } catch (_) {
      // Non-fatal: applies for this session.
    }
  }
}

// ── Providers ──────────────────────────────────────────────────────────────

final ideWorkspaceProvider =
    NotifierProvider<IdeWorkspaceNotifier, IdeWorkspaceState>(
        IdeWorkspaceNotifier.new);

final ideTabsProvider =
    NotifierProvider<IdeTabsNotifier, IdeTabsState>(IdeTabsNotifier.new);

final ideConsoleProvider =
    NotifierProvider<IdeConsoleNotifier, IdeConsoleState>(
        IdeConsoleNotifier.new);

final ideToolsProvider =
    NotifierProvider<IdeToolsNotifier, IdeToolsState>(IdeToolsNotifier.new);




