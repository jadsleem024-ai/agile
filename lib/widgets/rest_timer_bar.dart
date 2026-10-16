import 'package:flutter/material.dart';

class RestTimerBar extends StatelessWidget {
  final bool isActive;
  final int secondsRemaining;
  final int totalSeconds;
  final String label;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onReset;
  final bool showResetWhenIdle;

  const RestTimerBar({
    super.key,
    required this.isActive,
    required this.secondsRemaining,
    required this.totalSeconds,
    required this.label,
    required this.onStart,
    required this.onPause,
    required this.onReset,
    this.showResetWhenIdle = false,
  });

  String _format(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (isActive) {
      return Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF334155), borderRadius: BorderRadius.circular(14)),
              child: Column(
                children: [
                  Text(_format(secondsRemaining), style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  const Text('Rest Time', style: TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _iconBtn(Icons.pause, const Color(0xFFCA8A04), onPause),
          const SizedBox(width: 8),
          _iconBtn(Icons.replay, const Color(0xFF475569), onReset),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow),
            label: Text('Start Rest Timer (${totalSeconds}s)'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ),
        if (showResetWhenIdle) ...[
          const SizedBox(width: 8),
          _iconBtn(Icons.replay, const Color(0xFF334155), onReset),
        ],
      ],
    );
  }

  Widget _iconBtn(IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(14), child: Icon(icon, color: Colors.white)),
      ),
    );
  }
}
