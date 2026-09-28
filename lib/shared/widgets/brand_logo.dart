import 'package:flutter/material.dart';

/// The DocSync logo image asset.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 72});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/docsync_logo.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
    );
  }
}
