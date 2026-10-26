import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';

/// WhatsApp-style Swipe Left-to-Right gesture on message bubbles to trigger reply.
class SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final bool isMe;

  const SwipeToReply({
    super.key,
    required this.child,
    required this.onReply,
    required this.isMe,
  });

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late Animation<double> _animation;
  double _dragOffset = 0.0;
  bool _triggeredHaptic = false;

  static const double _replyThreshold = 48.0;
  static const double _maxDrag = 75.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = Tween<double>(begin: 0.0, end: 0.0).animate(_animController);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (details.primaryDelta == null) return;

    // Only allow left-to-right swipe (positive delta)
    final newOffset = (_dragOffset + details.primaryDelta!).clamp(0.0, _maxDrag);
    if (newOffset != _dragOffset) {
      setState(() {
        _dragOffset = newOffset;
      });

      if (_dragOffset >= _replyThreshold && !_triggeredHaptic) {
        _triggeredHaptic = true;
        HapticFeedback.lightImpact();
      } else if (_dragOffset < _replyThreshold) {
        _triggeredHaptic = false;
      }
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_dragOffset >= _replyThreshold) {
      widget.onReply();
    }
    _animateBack();
  }

  void _onHorizontalDragCancel() {
    _animateBack();
  }

  void _animateBack() {
    _animation = Tween<double>(begin: _dragOffset, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    )..addListener(() {
        setState(() {
          _dragOffset = _animation.value;
        });
      });
    _animController.forward(from: 0.0);
    _triggeredHaptic = false;
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dragOffset / _replyThreshold).clamp(0.0, 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      onHorizontalDragCancel: _onHorizontalDragCancel,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerLeft,
        children: [
          // WhatsApp Reply Circle Icon that appears on left behind bubble
          if (_dragOffset > 4)
            Positioned(
              left: 14 + (_dragOffset * 0.35).clamp(0.0, 22.0),
              child: Opacity(
                opacity: progress,
                child: Transform.scale(
                  scale: 0.6 + (progress * 0.4),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.ultraviolet.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.reply_rounded,
                      color: AppColors.ultraviolet,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),

          // Message Bubble that slides horizontally
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
