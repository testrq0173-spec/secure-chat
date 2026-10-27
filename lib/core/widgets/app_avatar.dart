import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/colors.dart';

class AppAvatar extends StatelessWidget {
  final String name;
  final double radius;
  final String? imageUrl;
  final bool isVerified;
  final bool isGroup;

  const AppAvatar({
    super.key,
    required this.name,
    this.radius = 24.0,
    this.imageUrl,
    this.isVerified = false,
    this.isGroup = false,
  });

  String _getInitials() {
    if (isGroup) return '#';
    final parts = name.trim().split(' ');
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length > 1 && parts[1].isNotEmpty) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  Widget _buildImageOrInitials() {
    if (imageUrl != null && imageUrl!.trim().isNotEmpty) {
      final path = imageUrl!.trim();
      final isLocal = !kIsWeb && (path.startsWith('/') || path.contains(r':\'));
      if (isLocal && File(path).existsSync()) {
        return ClipOval(
          child: Image.file(
            File(path),
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _buildInitials(),
          ),
        );
      }
    }
    return _buildInitials();
  }

  Widget _buildInitials() {
    return Center(
      child: Text(
        _getInitials(),
        style: TextStyle(
          color: AppColors.ultraviolet,
          fontSize: radius * 0.75,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            color: AppColors.lavender,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.white, width: 2),
            boxShadow: AppColors.softCardShadow,
          ),
          child: _buildImageOrInitials(),
        ),
        if (isVerified)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check,
                color: AppColors.white,
                size: 11,
              ),
            ),
          ),
      ],
    );
  }
}

class SecurityBadge extends StatelessWidget {
  final bool isVerified;
  final VoidCallback? onTap;

  const SecurityBadge({
    super.key,
    required this.isVerified,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isVerified ? AppColors.success.withValues(alpha: 0.12) : AppColors.grey200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isVerified ? Icons.verified_user_rounded : Icons.shield_outlined,
              size: 14,
              color: isVerified ? AppColors.success : AppColors.grey500,
            ),
            const SizedBox(width: 4),
            Text(
              isVerified ? 'Verified' : 'Unverified',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isVerified ? AppColors.success : AppColors.grey500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
