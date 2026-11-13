// Pure path helpers of the PC-only IDE core (no platform calls needed).
import 'package:flutter_test/flutter_test.dart';
import 'package:mide/features/ide/ide_providers.dart';

void main() {
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
