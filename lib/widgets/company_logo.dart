// lib/widgets/company_logo.dart
import 'package:flutter/material.dart';

/// LK Group logo used by the splash screen and shared app header.
///
/// The transparent company logo asset is preferred. The second asset and the
/// text/icon fallback keep the app usable when an asset is missing.
class CompanyLogo extends StatelessWidget {
  final double width;
  final double height;
  final bool white;

  // Backward-compatible parameters used by older screens.
  final double? size;
  final Color? color;

  const CompanyLogo({
    super.key,
    this.width = 108,
    this.height = 52,
    this.white = true,
    this.size,
    this.color,
  });

  double get _width => size ?? width;
  double get _height => size ?? height;
  Color get _color => color ?? (white ? Colors.white : Colors.black87);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
      height: _height,
      child: Image.asset(
        'assets/images/company_logo_transparent.png',
        width: _width,
        height: _height,
        fit: BoxFit.contain,
        color: white || color != null ? _color : null,
        colorBlendMode: white || color != null ? BlendMode.srcIn : null,
        errorBuilder: (context, error, stackTrace) => Image.asset(
          'assets/images/company_logo.png',
          width: _width,
          height: _height,
          fit: BoxFit.contain,
          color: white || color != null ? _color : null,
          colorBlendMode: white || color != null ? BlendMode.srcIn : null,
          errorBuilder: (_, __, ___) => _FallbackLogo(
            width: _width,
            height: _height,
            color: _color,
          ),
        ),
      ),
    );
  }
}

class _FallbackLogo extends StatelessWidget {
  final double width;
  final double height;
  final Color color;

  const _FallbackLogo({
    required this.width,
    required this.height,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_shipping, color: color, size: 34),
            const SizedBox(width: 5),
            Text(
              'LK Group',
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
