import 'package:flutter_test/flutter_test.dart';
import 'package:mide/features/updater/updater_types.dart';

void main() {
  group('compareVersions', () {
    test('compares dotted numeric versions', () {
      expect(compareVersions('1.0.1', '1.0.0'), greaterThan(0));
      expect(compareVersions('v1.0.0', '1.0'), 0);
      expect(compareVersions('1.0.0', '1.0.1'), lessThan(0));
    });

    test('ignores build metadata', () {
      expect(compareVersions('1.0.1+2', '1.0.1+1'), 0);
    });

    test('rejects invalid versions', () {
      expect(compareVersions('latest', '1.0.0'), isNull);
    });
  });

  group('androidArm64ApkFrom', () {
    test('selects only a secure GitHub Android arm64 APK', () {
      final asset = androidArm64ApkFrom([
        {
          'name': 'mide-windows-x64.exe',
          'browser_download_url': 'https://github.com/wxstdo-boop/Mide/file.exe',
        },
        {
          'name': 'mide-1.0.1-arm64-release.apk',
          'browser_download_url':
              'https://github.com/wxstdo-boop/Mide/releases/download/v1.0.1/app.apk',
          'size': 1024,
        },
      ]);

      expect(asset?.name, 'mide-1.0.1-arm64-release.apk');
      expect(asset?.sizeBytes, 1024);
    });

    test('does not fall back to an incompatible asset', () {
      expect(
        androidArm64ApkFrom([
          {
            'name': 'mide-windows-x64.exe',
            'browser_download_url':
                'https://github.com/wxstdo-boop/Mide/windows.exe',
          },
        ]),
        isNull,
      );
    });
  });
}
