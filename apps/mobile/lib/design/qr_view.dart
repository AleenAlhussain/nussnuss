import 'package:flutter/material.dart';

import '../core/qr.dart';

/// A QR code for [data], drawn from core/qr.dart (the same modules as the web). Always dark on
/// white with a four-module quiet zone, in every look, so every camera reads it.
class QrView extends StatelessWidget {
  const QrView({
    super.key,
    required this.data,
    required this.label,
    this.size = 196,
  });
  final String data;

  /// What a screen reader says ("Scan to join, https://…").
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    QrCode? code;
    try {
      code = encodeQr(data);
    } on FormatException {
      code = null;
    }
    if (code == null) return const SizedBox.shrink();
    return Semantics(
      label: label,
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(16),
        ),
        child: CustomPaint(painter: _QrPainter(code)),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.code);
  final QrCode code;

  @override
  void paint(Canvas canvas, Size size) {
    const quiet = 4;
    final cells = code.size + quiet * 2;
    final cell = size.shortestSide / cells;
    final paint = Paint()
      ..color = const Color(0xFF000000)
      ..isAntiAlias = false;
    final path = Path();
    for (var y = 0; y < code.size; y++) {
      for (var x = 0; x < code.size; x++) {
        if (!code.modules[y][x]) continue;
        // A hair of overlap so neighbouring modules never show a seam.
        path.addRect(
          Rect.fromLTWH(
            (x + quiet) * cell,
            (y + quiet) * cell,
            cell + 0.3,
            cell + 0.3,
          ),
        );
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.code != code;
}
