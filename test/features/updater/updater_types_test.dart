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
          'browser_download_url':
              'https://github.com/wxstdo-boop/Mide/file.exe',
        },
        {
          'name': 'mide-1.0.1-arm64-release.apk',
          'browser_download_url': 'https://github.com/wxstdo-boop/Mide/releases/download/v1.0.1/app.apk',
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

    test('ignores non-https and non-github asset URLs', () {
      expect(
        androidArm64ApkFrom([
          {
            'name': 'mide-1.0.1-arm64-release.apk',
            'browser_download_url': 'http://evil.example/app.apk',
          },
          {
            'name': 'mide-1.0.1-arm64-release.apk',
            'browser_download_url': 'https://evil.example/app.apk',
          },
        ]),
        isNull,
      );
    });

    test('picks the first matching asset when several are listed', () {
      final asset = androidArm64ApkFrom([
        {
          'name': 'mide-1.0.1-x86.apk',
          'browser_download_url': 'https://github.com/o/r/a.apk',
        },
        {
          'name': 'mide-1.0.1-arm64-release.apk',
          'browser_download_url': 'https://github.com/o/r/b.apk',
          'size': 2048,
        },
      ]);
      expect(asset?.name, 'mide-1.0.1-arm64-release.apk');
      expect(asset?.sizeBytes, 2048);
    });

    test('captures a well-formed sha256 digest', () {
      final hex = 'a' * 64;
      final asset = androidArm64ApkFrom([
        {
          'name': 'mide-1.0.1-arm64-release.apk',
          'browser_download_url': 'https://github.com/o/r/b.apk',
          'digest': 'sha256:$hex',
        },
      ]);
      expect(asset?.sha256, hex);
    });

    test('ignores a malformed digest', () {
      final asset = androidArm64ApkFrom([
        {
          'name': 'mide-1.0.1-arm64-release.apk',
          'browser_download_url': 'https://github.com/o/r/b.apk',
          'digest': 'sha256:not-a-hash',
        },
      ]);
      expect(asset?.sha256, isNull);
    });

    test('leaves sha256 null when the release publishes no digest', () {
      final asset = androidArm64ApkFrom([
        {
          'name': 'mide-1.0.1-arm64-release.apk',
          'browser_download_url': 'https://github.com/o/r/b.apk',
        },
      ]);
      expect(asset?.sha256, isNull);
    });
  });

  group('UpdateAsset.sizeMb', () {
    test('renders kilobytes under one megabyte', () {
      expect(
        const UpdateAsset(name: 'a', url: 'u', sizeBytes: 2048).sizeMb,
        '2 КБ',
      );
    });

    test('renders megabytes at or above one megabyte', () {
      expect(
        const UpdateAsset(
          name: 'a',
          url: 'u',
          sizeBytes: 2 * 1024 * 1024,
        ).sizeMb,
        '2.0 МБ',
      );
    });
  });

  group('UpdateCheckResult factories', () {
    test('hasUpdate requires kind update and an asset', () {
      final r = UpdateCheckResult.updateAvailable(
        latestVersion: '1.1.0',
        asset: const UpdateAsset(name: 'a', url: 'u'),
      );
      expect(r.hasUpdate, isTrue);
      expect(r.failed, isFalse);
    });

    test('failure reports failed and carries the message', () {
      final r = UpdateCheckResult.failure('boom');
      expect(r.failed, isTrue);
      expect(r.error, 'boom');
    });

    test('installerOpened copies the source and records the path', () {
      final source = UpdateCheckResult.updateAvailable(
        latestVersion: '1.1.0',
        asset: const UpdateAsset(name: 'a', url: 'u'),
        notes: 'n',
      );
      final opened = UpdateCheckResult.installerOpened(source, '/tmp/app.apk');
      expect(opened.kind, UpdateKind.installerOpened);
      expect(opened.latestVersion, '1.1.0');
      expect(opened.savedPath, '/tmp/app.apk');
      expect(opened.asset, source.asset);
    });
  });
}
