import 'package:flutter/material.dart';

/// One avatar used everywhere the co-pilot appears (chat empty state, message
/// bubbles, thinking indicator, history). Shows a chosen face illustration when
/// one is selected, otherwise a clean colored circle with the co-pilot's
/// initial. Pass in the name + avatar key the parent screen already loaded —
/// this widget does no database work, so it's cheap to render many at once.
///
/// avatarKey values:
///   'initial'  -> colored circle with first letter of [name] (default)
///   'f1'..'f3' -> assets/copilot/f1.png ... f3.png  (female faces)
///   'm1'..'m3' -> assets/copilot/m1.png ... m3.png  (male faces)
///
/// Goes in: lib/copilot/copilot_avatar.dart
class CopilotAvatar extends StatelessWidget {
  final String name;
  final String avatarKey;
  final double size;

  const CopilotAvatar({
    super.key,
    required this.name,
    this.avatarKey = 'initial',
    this.size = 36,
  });

  // Brand "cash green."
  static const Color _brandGreen = Color(0xFF1FB24A);

  bool get _hasFace => avatarKey.isNotEmpty && avatarKey != 'initial';

  @override
  Widget build(BuildContext context) {
    if (_hasFace) {
      return ClipOval(
        child: Image.asset(
          'assets/copilot/$avatarKey.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          // If the asset is missing for any reason, never break the UI —
          // fall back to the initial circle.
          errorBuilder: (_, __, ___) => _initialCircle(),
        ),
      );
    }
    return _initialCircle();
  }

  Widget _initialCircle() {
    final trimmed = name.trim();
    final letter = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: _brandGreen,
        shape: BoxShape.circle,
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.5,
          height: 1,
        ),
      ),
    );
  }
}
