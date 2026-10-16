import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

class VideoModal extends StatefulWidget {
  final String url;
  final String exerciseName;

  const VideoModal({super.key, required this.url, required this.exerciseName});

  static Future<void> show(BuildContext context, String url, String exerciseName) {
    return showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => VideoModal(url: url, exerciseName: exerciseName),
    );
  }

  @override
  State<VideoModal> createState() => _VideoModalState();
}

class _VideoModalState extends State<VideoModal> {
  YoutubePlayerController? _controller;
  bool _fullscreen = false;
  bool _invalidUrl = false;

  @override
  void initState() {
    super.initState();
    final videoId = YoutubePlayer.convertUrlToId(widget.url);
    if (videoId == null) {
      _invalidUrl = true;
    } else {
      _controller = YoutubePlayerController(
        initialVideoId: videoId,
        flags: const YoutubePlayerFlags(autoPlay: true, mute: false),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.all(_fullscreen ? 0 : 16),
      backgroundColor: Colors.transparent,
      child: Container(
        width: double.infinity,
        height: _fullscreen ? double.infinity : null,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(_fullscreen ? 0 : 20),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Column(
          mainAxisSize: _fullscreen ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                border: Border(bottom: BorderSide(color: Color(0xFF334155))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.exerciseName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        const Text('How to perform this exercise', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(_fullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
                    onPressed: () => setState(() => _fullscreen = !_fullscreen),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            if (_fullscreen)
              Expanded(child: _buildPlayer())
            else
              _buildPlayer(),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayer() {
    if (_invalidUrl || _controller == null) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(
          child: Text('Invalid video link', style: TextStyle(color: Colors.white70)),
        ),
      );
    }
    return YoutubePlayer(
      controller: _controller!,
      showVideoProgressIndicator: true,
      progressIndicatorColor: const Color(0xFF16A34A),
    );
  }
}