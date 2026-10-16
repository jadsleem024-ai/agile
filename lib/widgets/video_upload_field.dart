import 'package:flutter/material.dart';

/// A form field for entering a YouTube video URL, with validation
/// and a thumbnail preview once a valid link is detected.
class VideoUploadField extends StatefulWidget {
  final String? videoUrl;
  final ValueChanged<String?> onChanged;

  const VideoUploadField({super.key, required this.videoUrl, required this.onChanged});

  @override
  State<VideoUploadField> createState() => _VideoUploadFieldState();
}

class _VideoUploadFieldState extends State<VideoUploadField> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.videoUrl ?? '');
  }

  @override
  void didUpdateWidget(covariant VideoUploadField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl && widget.videoUrl != _controller.text) {
      _controller.text = widget.videoUrl ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Extracts the 11-character YouTube video ID from common URL formats.
  static String? _extractVideoId(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    final patterns = [
      RegExp(r'(?:youtube\.com\/watch\?v=)([A-Za-z0-9_-]{11})'),
      RegExp(r'(?:youtu\.be\/)([A-Za-z0-9_-]{11})'),
      RegExp(r'(?:youtube\.com\/shorts\/)([A-Za-z0-9_-]{11})'),
      RegExp(r'(?:youtube\.com\/embed\/)([A-Za-z0-9_-]{11})'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(trimmed);
      if (match != null) return match.group(1);
    }
    return null;
  }

  void _onFieldChanged(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() => _error = null);
      widget.onChanged(null);
      return;
    }
    final videoId = _extractVideoId(trimmed);
    if (videoId == null) {
      setState(() => _error = 'Enter a valid YouTube URL');
      widget.onChanged(null);
    } else {
      setState(() => _error = null);
      widget.onChanged(trimmed);
    }
  }

  void _clear() {
    _controller.clear();
    _onFieldChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final videoId = _extractVideoId(_controller.text);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF334155),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF475569)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.videocam_outlined, size: 16, color: Colors.white70),
              SizedBox(width: 6),
              Text('Exercise Video (Optional)', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            onChanged: _onFieldChanged,
            keyboardType: TextInputType.url,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'https://www.youtube.com/watch?v=...',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
              prefixIcon: const Icon(Icons.link, size: 18, color: Colors.white54),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.redAccent),
                onPressed: _clear,
              )
                  : null,
              errorText: _error,
              filled: true,
              fillColor: const Color(0xFF1E293B),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          if (videoId != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.network(
                    'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
                    width: double.infinity,
                    height: 160,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: double.infinity,
                      height: 160,
                      color: const Color(0xFF1E293B),
                      child: const Icon(Icons.videocam_off_outlined, color: Colors.white38, size: 32),
                    ),
                  ),
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), shape: BoxShape.circle),
                    child: const Icon(Icons.play_arrow, color: Colors.white, size: 30),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}