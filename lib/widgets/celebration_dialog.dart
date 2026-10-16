import 'dart:math';
import 'package:flutter/material.dart';
import '../data/quotes.dart';

/// The reward for finishing a session: confetti, a headline scaled to how much
/// was actually done, and a random quote.
///
/// The confetti is hand-painted rather than pulled from a package — it is a few
/// dozen falling rectangles and not worth a dependency.
class CelebrationDialog extends StatefulWidget {
  final String programName;
  final int completedSets;
  final int totalSets;


  const CelebrationDialog({
    super.key,
    required this.programName,
    required this.completedSets,
    required this.totalSets,
  });

  static Future<void> show(
    BuildContext context, {
    required String programName,
    required int completedSets,
    required int totalSets,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      builder: (_) => CelebrationDialog(
        programName: programName,
        completedSets: completedSets,
        totalSets: totalSets,
      ),
    );
  }

  @override
  State<CelebrationDialog> createState() => _CelebrationDialogState();
}

class _CelebrationDialogState extends State<CelebrationDialog>
    with TickerProviderStateMixin {
  late final AnimationController _confettiController;
  late final AnimationController _popController;
  late final List<_Confetto> _confetti;
  late final String _quote;

  @override
  void initState() {
    super.initState();
    _quote = randomQuote();
    _confetti = _Confetto.spawn(60);
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..forward();
    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    )..forward();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _popController.dispose();
    super.dispose();
  }

  double get _percent =>
      widget.totalSets > 0 ? (widget.completedSets / widget.totalSets) * 100 : 0;

  @override
  Widget build(BuildContext context) {
    final headline = celebrationHeadline(_percent);

    // Without a Material ancestor every Text here renders with Flutter's
    // yellow "missing Material" double underline — showDialog hands us a bare
    // route, and this Stack was sitting directly under it.
    return Material(
      type: MaterialType.transparency,
      child: Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _confettiController,
              builder: (_, __) => CustomPaint(
                painter: _ConfettiPainter(_confetti, _confettiController.value),
              ),
            ),
          ),
        ),
        Center(
          child: ScaleTransition(
            scale: CurvedAnimation(parent: _popController, curve: Curves.elasticOut),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.all(26),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: const Color(0xFF22C55E), width: 1.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 78,
                      height: 78,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFF16A34A), Color(0xFF059669)],
                        ),
                      ),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 46),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      headline,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${widget.programName} · ${widget.completedSets}/${widget.totalSets} sets logged',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF334155),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.format_quote, color: Color(0xFF94A3B8), size: 20),
                          const SizedBox(height: 6),
                          Text(
                            _quote,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              height: 1.5,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                        ),
                        child: const Text('Nice!',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
      ),
    );
  }
}

class _Confetto {
  final double x; // 0..1 of width
  final double delay; // 0..1 of the animation
  final double speed;
  final double drift;
  final double size;
  final double rotation;
  final Color color;

  _Confetto({
    required this.x,
    required this.delay,
    required this.speed,
    required this.drift,
    required this.size,
    required this.rotation,
    required this.color,
  });

  static const _palette = [
    Color(0xFF22C55E),
    Color(0xFF3B82F6),
    Color(0xFFFACC15),
    Color(0xFFEC4899),
    Color(0xFF9333EA),
    Color(0xFFF97316),
  ];

  static List<_Confetto> spawn(int count) {
    final rnd = Random();
    return List.generate(count, (_) {
      return _Confetto(
        x: rnd.nextDouble(),
        delay: rnd.nextDouble() * 0.35,
        speed: 0.7 + rnd.nextDouble() * 0.6,
        drift: (rnd.nextDouble() - 0.5) * 0.25,
        size: 6 + rnd.nextDouble() * 8,
        rotation: rnd.nextDouble() * pi * 2,
        color: _palette[rnd.nextInt(_palette.length)],
      );
    });
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_Confetto> pieces;
  final double t; // 0..1

  _ConfettiPainter(this.pieces, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    for (final c in pieces) {
      final local = ((t - c.delay) / (1 - c.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;

      final progress = local * c.speed;
      final dy = progress * (size.height + 80) - 40;
      if (dy > size.height + 40) continue;

      final dx = (c.x + c.drift * local) * size.width;
      // Fade out over the last third of the fall.
      final opacity = local > 0.7 ? (1 - (local - 0.7) / 0.3).clamp(0.0, 1.0) : 1.0;

      paint.color = c.color.withOpacity(opacity);

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(c.rotation + progress * 8);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: c.size, height: c.size * 0.55),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}
