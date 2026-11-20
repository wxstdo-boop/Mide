// Pure path helpers of the PC-only IDE core (no platform calls needed).
import 'package:flutter_test/flutter_test.dart';
import 'package:mide/features/ide/ide_ai.dart';
import 'package:mide/features/ide/ide_providers.dart';

void main() {
  _aiContract();

  group('ideBaseName', () {
    test('handles forward slashes', () {
      expect(ideBaseName('/home/user/project/main.dart'), 'main.dart');
    });

    test('handles Windows backslashes', () {
      expect(ideBaseName(r'C:\Users\dev\project\main.dart'), 'main.dart');
    });

    test('returns the input when there is no separator', () {
      expect(ideBaseName('main.dart'), 'main.dart');
    });
  });

  group('ideParentOf', () {
    test('strips the last forward-slash segment', () {
      expect(ideParentOf('/home/user/main.dart'), '/home/user');
    });

    test('strips the last backslash segment', () {
      expect(ideParentOf(r'C:\dev\main.dart'), r'C:\dev');
    });

    test('collapses a Windows drive-root child to its drive', () {
      // Parent of a file sitting directly under a drive root.
      expect(ideParentOf(r'C:\file.txt'), 'C:');
    });

    test('returns the input when there is no separator', () {
      expect(ideParentOf('main.dart'), 'main.dart');
    });
  });
}

// Guard the anonymous-first contract: the IDE must be able to answer with no
// key, and every id it rotates through must still exist upstream.
void _aiContract() {
  group('IDE AI providers', () {
    test('Kilo stays anonymous: no auth header on the free rotation', () {
      expect(kiloProvider.authHeader, isNull);
      expect(kiloProvider.needsKey, isFalse);
    });

    test('Kilo free ids are the live ones, not the retired 404s', () {
      // The two retired ids answered 404 "model does not exist", which burned
      // a rotation slot on every message.
      expect(kiloProvider.models, isNot(contains('minimax/minimax-m2.1:free')));
      expect(kiloProvider.models, isNot(contains('z-ai/glm-5:free')));
      expect(kiloProvider.models, contains('kilo-auto/free'));
    });

    test('every IDE provider answers without a user-supplied key', () {
      for (final p in ideCodingProviders) {
        expect(
          p.needsKey,
          isFalse,
          reason: '${p.label} would block a fresh install',
        );
      }
    });

    test('Kilo is tried before the slower fallbacks', () {
      expect(ideCodingProviders.first.label, 'Kilo');
    });
  });
}
