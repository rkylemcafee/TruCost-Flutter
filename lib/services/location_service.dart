import 'package:geolocator/geolocator.dart';

/// A location failure carrying a message the UI can show as-is.
class LocationException implements Exception {
  final String message;
  LocationException(this.message);
  @override
  String toString() => message;
}

/// Shared GPS access with a **once-per-session** permission prompt.
///
/// The problem this solves: every screen used to run its own
/// check-then-request dance, so the driver got asked for location again each
/// place they went. Here the permission is resolved a single time per app
/// session and cached; every later request reuses that answer and goes
/// straight to the fix — no repeat prompts.
///
/// Route all location access through [getPosition] / [getLatLngString] so the
/// whole app shares the one cached answer.
class LocationService {
  static LocationPermission? _sessionPermission;

  /// Call on sign-out if you want the next session to prompt fresh.
  static void resetSession() => _sessionPermission = null;

  /// Whether we've already resolved permission this session.
  static bool get resolvedThisSession => _sessionPermission != null;

  /// Get the current position, prompting for permission only the first time
  /// this session. Throws [LocationException] with a user-ready message if
  /// services are off or permission isn't granted.
  static Future<Position> getPosition({
    LocationAccuracy accuracy = LocationAccuracy.medium,
  }) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationException(
          'Location services are off. Turn them on in Settings.');
    }

    // Resolve permission exactly once per session. After it's cached we never
    // call requestPermission again, so the driver isn't re-asked screen to
    // screen. (A fresh app launch starts a new session and may ask once.)
    if (_sessionPermission == null) {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      _sessionPermission = permission;
    }

    final permission = _sessionPermission!;
    if (permission == LocationPermission.denied) {
      throw LocationException('Location permission denied.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationException(
          'Location permission permanently denied. Enable it in Settings.');
    }

    return Geolocator.getCurrentPosition(desiredAccuracy: accuracy);
  }

  /// Convenience wrapper returning a `"lat,lng"` string.
  static Future<String> getLatLngString({
    LocationAccuracy accuracy = LocationAccuracy.medium,
  }) async {
    final pos = await getPosition(accuracy: accuracy);
    return '${pos.latitude},${pos.longitude}';
  }
}
