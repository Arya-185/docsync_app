// Builds the launcher-icon masters from the DocSync logo.
//
//   dart run tool/make_icons.dart && dart run flutter_launcher_icons
//
// The logo is wider than it is tall (~349x286). Handing it straight to flutter_launcher_icons
// stretches it into a square with no margin, and the adaptive foreground then overflows the
// circular safe zone. Here the logo is trimmed, scaled with its aspect ratio kept, and centred
// on a square canvas with room around it.
import 'dart:io';

import 'package:image/image.dart' as img;

const _canvas = 1024;

void main() {
  final raw = img.decodePng(File('assets/images/docsync_logo.png').readAsBytesSync());
  if (raw == null) {
    stderr.writeln('could not decode assets/images/docsync_logo.png');
    exit(1);
  }
  final logo = img.trim(raw.convert(numChannels: 4), mode: img.TrimMode.topLeftColor);
  Directory('assets/icon').createSync(recursive: true);

  // Legacy icon (API < 26): the logo on white, ~70% of the width.
  _write(logo, 'assets/icon/app_icon.png', fraction: 0.70, background: img.ColorRgba8(255, 255, 255, 255));

  // Adaptive foreground: transparent, ~66% of the width. flutter_launcher_icons adds a 16% inset,
  // so the logo ends up ~45% of the 108dp canvas, its diagonal inside the 66dp safe circle.
  _write(logo, 'assets/icon/app_icon_fg.png', fraction: 0.66, background: img.ColorRgba8(0, 0, 0, 0));

  stdout.writeln('wrote assets/icon/app_icon.png and assets/icon/app_icon_fg.png');
}

void _write(img.Image logo, String path, {required double fraction, required img.Color background}) {
  final maxSide = (_canvas * fraction).round();
  final scale = maxSide / (logo.width > logo.height ? logo.width : logo.height);
  final w = (logo.width * scale).round();
  final h = (logo.height * scale).round();
  final resized = img.copyResize(logo, width: w, height: h, interpolation: img.Interpolation.cubic);

  final out = img.Image(width: _canvas, height: _canvas, numChannels: 4);
  img.fill(out, color: background);
  img.compositeImage(out, resized, dstX: (_canvas - w) ~/ 2, dstY: (_canvas - h) ~/ 2);
  File(path).writeAsBytesSync(img.encodePng(out));
}
