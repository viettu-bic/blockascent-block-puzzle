import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// An inventory test for the generated app icon, in the spirit of
/// `test/platform/sfx_test.dart`: the icon is produced by
/// `tool/make_icon.py`, and a generated asset that is missing, the wrong size
/// or the wrong format fails at submission rather than at runtime, which is
/// the worst place to find out.
///
/// Three things it catches that nothing else would:
///
/// - **An iOS icon with an alpha channel.** App Store Connect rejects the
///   build, hours after the upload. The generator writes 8-bit RGB for every
///   iOS size on purpose; this proves it stayed that way.
/// - **A size in `Contents.json` with no PNG behind it**, which is what
///   happens when Xcode adds an idiom and nobody regenerates.
/// - **An adaptive layer that was not regenerated with the others**, so a
///   launcher composites last week's foreground onto this week's sky.
void main() {
  /// (width, height, colourType). PNG colour type 2 is RGB, 6 is RGBA.
  (int, int, int) readPngHeader(File f) {
    final b = f.readAsBytesSync();
    expect(
      b.sublist(0, 8),
      [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
      reason: '${f.path} is not a PNG',
    );
    int be32(int at) =>
        (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];
    expect(String.fromCharCodes(b.sublist(12, 16)), 'IHDR');
    return (be32(16), be32(20), b[25]);
  }

  void expectIcon(String path, int size, {required bool alpha}) {
    final f = File(path);
    expect(f.existsSync(), isTrue, reason: '$path is missing — run tool/make_icon.py');
    final (w, h, type) = readPngHeader(f);
    expect(w, size, reason: '$path width');
    expect(h, size, reason: '$path height');
    expect(
      type,
      alpha ? 6 : 2,
      reason: alpha ? '$path should carry alpha' : '$path must not carry alpha',
    );
  }

  const androidLegacy = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
  };

  const ios = {
    'Icon-App-20x20@1x.png': 20,
    'Icon-App-20x20@2x.png': 40,
    'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29,
    'Icon-App-29x29@2x.png': 58,
    'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40,
    'Icon-App-40x40@2x.png': 80,
    'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120,
    'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76,
    'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167,
    'Icon-App-1024x1024@1x.png': 1024,
  };

  const res = 'android/app/src/main/res';
  const appIcon = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';

  group('android', () {
    test('every density has a legacy icon at the right size', () {
      androidLegacy.forEach((folder, size) {
        expectIcon('$res/$folder/ic_launcher.png', size, alpha: false);
      });
    });

    test('every density has all three adaptive layers on a 108dp canvas', () {
      androidLegacy.forEach((folder, size) {
        final n = (size * 108 / 48).round();
        expectIcon('$res/$folder/ic_launcher_background.png', n, alpha: false);
        expectIcon('$res/$folder/ic_launcher_foreground.png', n, alpha: true);
        expectIcon('$res/$folder/ic_launcher_monochrome.png', n, alpha: true);
      });
    });

    test('the adaptive icon names all three layers', () {
      final xml = File('$res/mipmap-anydpi-v26/ic_launcher.xml').readAsStringSync();
      expect(xml, contains('@mipmap/ic_launcher_background'));
      expect(xml, contains('@mipmap/ic_launcher_foreground'));
      expect(xml, contains('@mipmap/ic_launcher_monochrome'));
    });

    test('the launch window is the game background, not white', () {
      // A dark-first game that opens white announces itself with a flash.
      expect(
        File('$res/values/colors.xml').readAsStringSync(),
        contains('#FF14161C'),
      );
      for (final dir in ['drawable', 'drawable-v21']) {
        expect(
          File('$res/$dir/launch_background.xml').readAsStringSync(),
          contains('@color/night'),
        );
      }
      for (final dir in ['values', 'values-night']) {
        expect(
          File('$res/$dir/styles.xml').readAsStringSync(),
          isNot(contains('?android:colorBackground')),
        );
      }
    });
  });

  group('ios', () {
    test('every size exists, is square, and carries no alpha', () {
      ios.forEach((name, size) {
        expectIcon('$appIcon/$name', size, alpha: false);
      });
    });

    test('Contents.json asks for nothing that is not generated', () {
      final json = jsonDecode(File('$appIcon/Contents.json').readAsStringSync());
      final wanted = <String>{
        for (final i in (json['images'] as List))
          if (i['filename'] != null) i['filename'] as String,
      };
      expect(wanted.difference(ios.keys.toSet()), isEmpty);
    });

    test('the launch image is generated too', () {
      const launch = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
      for (final (name, size) in [
        ('LaunchImage.png', 96),
        ('LaunchImage@2x.png', 192),
        ('LaunchImage@3x.png', 288),
      ]) {
        expectIcon('$launch/$name', size, alpha: false);
      }
    });
  });
}
