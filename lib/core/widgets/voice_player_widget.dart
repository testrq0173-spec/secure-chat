import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../theme/colors.dart';

class VoicePlayerWidget extends StatefulWidget {
  final String? filePath;
  final int? durationMs;
  final bool isMe;

  const VoicePlayerWidget({
    super.key,
    required this.filePath,
    this.durationMs,
    required this.isMe,
  });

  @override
  State<VoicePlayerWidget> createState() => _VoicePlayerWidgetState();
}

class _VoicePlayerWidgetState extends State<VoicePlayerWidget> {
  AudioPlayer? _player;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _totalDuration = Duration(milliseconds: widget.durationMs ?? 3000);
    _initAudio();
  }

  Future<void> _initAudio() async {
    if (widget.filePath == null) return;
    final file = File(widget.filePath!);
    if (!await file.exists()) return;

    try {
      _player = AudioPlayer();
      await _player!.setFilePath(widget.filePath!);
      _totalDuration = _player!.duration ?? _totalDuration;
      _isLoaded = true;

      _player!.playerStateStream.listen((state) {
        if (!mounted) return;
        setState(() {
          _isPlaying = state.playing && state.processingState != ProcessingState.completed;
          if (state.processingState == ProcessingState.completed) {
            _position = Duration.zero;
          }
        });
      });

      _player!.positionStream.listen((pos) {
        if (!mounted) return;
        setState(() => _position = pos);
      });
    } catch (_) {
      // Audio load fallback
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  void _togglePlay() async {
    if (_player == null || !_isLoaded) return;
    if (_isPlaying) {
      await _player!.pause();
    } else {
      if (_position >= _totalDuration) {
        await _player!.seek(Duration.zero);
      }
      await _player!.play();
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(1, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isMe ? AppColors.white : AppColors.ink;
    final progress = _totalDuration.inMilliseconds > 0
        ? (_position.inMilliseconds / _totalDuration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _togglePlay,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.isMe ? AppColors.white : AppColors.ultraviolet,
            ),
            child: Icon(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: widget.isMe ? AppColors.ultraviolet : AppColors.white,
              size: 22,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Waveform bar progress
            SizedBox(
              width: 120,
              height: 20,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(
                      18,
                      (i) {
                        final barProgress = i / 18.0;
                        final isFilled = barProgress <= progress;
                        return Container(
                          width: 3,
                          height: 6 + (i % 5) * 3.5,
                          decoration: BoxDecoration(
                            color: isFilled
                                ? (widget.isMe ? AppColors.white : AppColors.ultraviolet)
                                : textColor.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _isPlaying ? _formatDuration(_position) : _formatDuration(_totalDuration),
              style: TextStyle(
                fontSize: 11,
                color: textColor.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
