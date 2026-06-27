import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'auth/auth_gate.dart';

/// Branded intro splash: plays the truck→logo animation, then hands off to
/// AuthGate. This is NOT the native launch screen (that stays a static image);
/// it's the first Flutter screen, shown after the app boots.
///
/// Never blocks the user:
///   • Tap anywhere — or the Skip button — to leave immediately.
///   • Auto-advances the moment the clip finishes.
///   • Hard 8s timeout guarantees we leave even if the video never loads.
///
/// Controlled by the 'intro_enabled' pref (default true). When disabled, this
/// screen forwards to AuthGate on the first frame with no delay.
///
/// Goes in: lib/splash_intro.dart   (set as MaterialApp `home:`)
class SplashIntro extends StatefulWidget {
  const SplashIntro({super.key});

  @override
  State<SplashIntro> createState() => _SplashIntroState();
}

class _SplashIntroState extends State<SplashIntro> {
  VideoPlayerController? _controller;
  Timer? _timeout;
  bool _navigated = false;

  static const _asset = 'assets/trucost-copilot-splash.mp4';
  static const _prefKey = 'intro_enabled';
  static const _hardTimeout = Duration(seconds: 8); // safety net

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    // Read the user's setting. If prefs fail for any reason, default to showing.
    bool enabled = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool(_prefKey) ?? true;
    } catch (_) {
      enabled = true;
    }

    if (!enabled) {
      _go();
      return;
    }

    // No matter what happens with the video, we leave the splash by this point.
    _timeout = Timer(_hardTimeout, _go);

    try {
      final c = VideoPlayerController.asset(_asset);
      _controller = c;
      await c.initialize();
      await c.setVolume(0); // muted — autoplay-with-sound is its own headache
      c.addListener(_onTick);
      await c.play();
      if (mounted) setState(() {});
    } catch (_) {
      _go(); // asset missing / unplayable → straight through to AuthGate
    }
  }

  void _onTick() {
    final c = _controller;
    if (c == null) return;
    final v = c.value;
    // Playback reached the end → move on.
    if (v.isInitialized &&
        !v.isPlaying &&
        v.duration > Duration.zero &&
        v.position >= v.duration) {
      _go();
    }
  }

  void _go() {
    if (_navigated || !mounted) return;
    _navigated = true;
    _timeout?.cancel();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AuthGate()),
    );
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _go, // tap anywhere to skip
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready)
              FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: c.value.size.width,
                  height: c.value.size.height,
                  child: VideoPlayer(c),
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            Positioned(
              bottom: 16,
              right: 16,
              child: SafeArea(
                child: TextButton(
                  onPressed: _go,
                  child: const Text(
                    'Skip',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
