// Real-filesystem tests for the IDE workspace + tab notifiers.
// Uses a throw-away temp directory; exercises the actual dart:io code paths.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mide/features/ide/ide_providers.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mide_ide_test_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('IdeWorkspaceNotifier', () {
    test('opens a folder, reads children and hides build noise', () {
      File('${tmp.path}${Platform.pathSeparator}a.dart').writeAsStringSync('x');
      Directory('${tmp.path}${Platform.pathSeparator}sub').createSync();
      Directory('${tmp.path}${Platform.pathSeparator}build').createSync();
      Directory('${tmp.path}${Platform.pathSeparator}.git').createSync();

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(ideWorkspaceProvider.notifier);

      expect(notifier.openFolder(tmp.path), isNull);

      final state = container.read(ideWorkspaceProvider);
      expect(state.isOpen, isTrue);
      final names = state.children[state.root]!.map((n) => n.name).toList();
      expect(names, contains('a.dart'));
      expect(names, contains('sub'));
      // Hidden build dirs are filtered out.
      expect(names, isNot(contains('build')));
      expect(names, isNot(contains('.git')));
      // Directories sort before files.
      expect(names.first, 'sub');
    });

    test('rejects an empty path and a missing folder', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(ideWorkspaceProvider.notifier);

      expect(notifier.openFolder('   '), 'Путь пустой');
      expect(
        notifier.openFolder('${tmp.path}${Platform.pathSeparator}nope'),
        startsWith('Папка не найдена'),
      );
    });

    test('createEntry makes a file and reports a duplicate', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(ideWorkspaceProvider.notifier);
      notifier.openFolder(tmp.path);

      expect(
        notifier.createEntry(
          parentPath: tmp.path,
          asDir: false,
          name: 'new.txt',
        ),
        isNull,
      );
      expect(
        File('${tmp.path}${Platform.pathSeparator}new.txt').existsSync(),
        isTrue,
      );

      expect(
        notifier.createEntry(
          parentPath: tmp.path,
          asDir: false,
          name: 'new.txt',
        ),
        startsWith('Уже существует'),
      );
    });

    test('createEntry rejects separators in the name', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(ideWorkspaceProvider.notifier);
      notifier.openFolder(tmp.path);

      expect(
        notifier.createEntry(parentPath: tmp.path, asDir: false, name: 'a/b'),
        'Имя не может содержать "/" или "\\"',
      );
    });
  });

  group('IdeTabsNotifier', () {
    test('opens a file, tracks dirty state and saves', () async {
      final path = '${tmp.path}${Platform.pathSeparator}f.txt';
      File(path).writeAsStringSync('hello');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(ideTabsProvider.notifier);

      expect(await notifier.openFile(path), isNull);
      var state = container.read(ideTabsProvider);
      expect(state.activeTab!.content, 'hello');
      expect(state.activeTab!.dirty, isFalse);

      notifier.setContent(path, 'hello world');
      state = container.read(ideTabsProvider);
      expect(state.activeTab!.dirty, isTrue);
      expect(notifier.hasDirty, isTrue);

      expect(await notifier.save(), isNull);
      state = container.read(ideTabsProvider);
      expect(state.activeTab!.dirty, isFalse);
      expect(File(path).readAsStringSync(), 'hello world');
    });

    test(
      'opening the same path twice activates instead of duplicating',
      () async {
        final path = '${tmp.path}${Platform.pathSeparator}f.txt';
        File(path).writeAsStringSync('a');

        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(ideTabsProvider.notifier);

        await notifier.openFile(path);
        await notifier.openFile(path);
        expect(container.read(ideTabsProvider).tabs.length, 1);
      },
    );

    test('refuses to open a binary file', () async {
      final path = '${tmp.path}${Platform.pathSeparator}bin.dat';
      File(path).writeAsBytesSync([0, 1, 2, 0, 4]);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(ideTabsProvider.notifier);

      expect(await notifier.openFile(path), startsWith('Бинарный файл'));
      expect(container.read(ideTabsProvider).tabs, isEmpty);
    });

    test('closing the active tab keeps a valid neighbour active', () async {
      final a = '${tmp.path}${Platform.pathSeparator}a.txt';
      final b = '${tmp.path}${Platform.pathSeparator}b.txt';
      File(a).writeAsStringSync('a');
      File(b).writeAsStringSync('b');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(ideTabsProvider.notifier);

      await notifier.openFile(a);
      await notifier.openFile(b);
      expect(container.read(ideTabsProvider).active, 1);

      notifier.close(1);
      final state = container.read(ideTabsProvider);
      expect(state.tabs.length, 1);
      expect(state.activeTab!.name, 'a.txt');
    });
  });
}
