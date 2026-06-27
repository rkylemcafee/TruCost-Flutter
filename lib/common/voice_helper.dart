import 'package:flutter_tts/flutter_tts.dart';

/// Ranks the device's installed TTS voices and picks the best one.
///
/// Sort order: quality (Premium → Enhanced → Standard), then gender
/// (configurable), then name A–Z. Apple doesn't always expose quality/gender
/// on each voice, so we infer them from the identifier and a name table.
///
/// Goes in: lib/common/voice_helper.dart

enum VoiceQuality { premium, enhanced, standard } // index = rank (0 best)
enum VoiceGender { male, female, unknown }
enum GenderPref { maleFirst, femaleFirst, none }

class RankedVoice {
  final String name;
  final String locale;
  final String? identifier;
  final VoiceQuality quality;
  final VoiceGender gender;
  final Map<String, String> raw; // pass straight to flutterTts.setVoice

  const RankedVoice({
    required this.name,
    required this.locale,
    required this.identifier,
    required this.quality,
    required this.gender,
    required this.raw,
  });

  String get qualityLabel {
    switch (quality) {
      case VoiceQuality.premium:
        return 'Premium';
      case VoiceQuality.enhanced:
        return 'Enhanced';
      case VoiceQuality.standard:
        return 'Standard';
    }
  }

  String get genderLabel {
    switch (gender) {
      case VoiceGender.male:
        return 'Male';
      case VoiceGender.female:
        return 'Female';
      case VoiceGender.unknown:
        return '';
    }
  }
}

class VoiceHelper {
  /// Default gender tiebreaker. Evan reads as a male persona, so male voices
  /// sort first — flip to femaleFirst here if you'd rather.
  static GenderPref defaultGenderPref = GenderPref.maleFirst;

  /// All English voices on this device, best first.
  static Future<List<RankedVoice>> ranked(
    FlutterTts tts, {
    String lang = 'en',
    GenderPref? pref,
  }) async {
    final gp = pref ?? defaultGenderPref;
    final dynamic rawVoices = await tts.getVoices;
    final out = <RankedVoice>[];

    if (rawVoices is List) {
      for (final v in rawVoices) {
        if (v is! Map) continue;
        final m = Map<String, dynamic>.from(v);
        final locale = (m['locale'] ?? m['language'] ?? '').toString();
        if (!locale.toLowerCase().startsWith(lang.toLowerCase())) continue;

        final name = (m['name'] ?? '').toString();
        out.add(RankedVoice(
          name: name,
          locale: locale,
          identifier: m['identifier']?.toString(),
          quality: _quality(m),
          gender: _gender(m, name),
          raw: {'name': name, 'locale': locale},
        ));
      }
    }

    out.sort((a, b) {
      final q = a.quality.index.compareTo(b.quality.index);
      if (q != 0) return q;
      final g = _genderRank(a.gender, gp).compareTo(_genderRank(b.gender, gp));
      if (g != 0) return g;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  /// The single best installed voice (or null if none in [lang]).
  static Future<RankedVoice?> best(
    FlutterTts tts, {
    String lang = 'en',
    GenderPref? pref,
  }) async {
    final list = await ranked(tts, lang: lang, pref: pref);
    return list.isEmpty ? null : list.first;
  }

  /// Picks the best voice and applies it to [tts]. Returns what it chose.
  static Future<RankedVoice?> applyBest(
    FlutterTts tts, {
    String lang = 'en',
    GenderPref? pref,
  }) async {
    final b = await best(tts, lang: lang, pref: pref);
    if (b != null) {
      try {
        await tts.setVoice(b.raw);
      } catch (_) {}
    }
    return b;
  }

  /// Apply a saved voice by identifier if it's still installed; otherwise fall
  /// back to the best available. Returns the voice actually applied.
  static Future<RankedVoice?> applySavedOrBest(
    FlutterTts tts, {
    String? savedIdentifier,
    String? savedName,
    String lang = 'en',
    GenderPref? pref,
  }) async {
    final list = await ranked(tts, lang: lang, pref: pref);
    RankedVoice? match;
    if (savedIdentifier != null) {
      for (final v in list) {
        if (v.identifier == savedIdentifier) {
          match = v;
          break;
        }
      }
    }
    if (match == null && savedName != null) {
      for (final v in list) {
        if (v.name == savedName) {
          match = v;
          break;
        }
      }
    }
    match ??= list.isEmpty ? null : list.first;
    if (match != null) {
      try {
        await tts.setVoice(match.raw);
      } catch (_) {}
    }
    return match;
  }

  /// Public wrappers so other screens reuse the same quality/gender logic.
  static VoiceQuality qualityForMap(Map m) => _quality(m);
  static VoiceGender genderForName(String name) => _genderByName(name);

  // ── inference ──

  static VoiceQuality _quality(Map m) {
    final q = (m['quality'] ?? '').toString().toLowerCase();
    if (q.contains('premium')) return VoiceQuality.premium;
    if (q.contains('enhanced')) return VoiceQuality.enhanced;
    final id = '${m['identifier'] ?? ''} ${m['name'] ?? ''}'.toLowerCase();
    if (id.contains('premium')) return VoiceQuality.premium;
    if (id.contains('enhanced')) return VoiceQuality.enhanced;
    return VoiceQuality.standard;
  }

  static VoiceGender _gender(Map m, String name) {
    final g = (m['gender'] ?? '').toString().toLowerCase();
    if (g.startsWith('m')) return VoiceGender.male;
    if (g.startsWith('f')) return VoiceGender.female;
    return _genderByName(name);
  }

  static int _genderRank(VoiceGender g, GenderPref pref) {
    if (pref == GenderPref.none) return 0;
    final maleFirst = pref == GenderPref.maleFirst;
    switch (g) {
      case VoiceGender.male:
        return maleFirst ? 0 : 1;
      case VoiceGender.female:
        return maleFirst ? 1 : 0;
      case VoiceGender.unknown:
        return 2;
    }
  }

  // Common Apple English voices. Anything unlisted falls through to unknown.
  static const Set<String> _male = {
    'aaron', 'albert', 'alex', 'arthur', 'bad news', 'bahh', 'bells', 'boing',
    'bubbles', 'cellos', 'daniel', 'eddy', 'fred', 'gordon', 'grandpa', 'jester',
    'junior', 'lee', 'oliver', 'organ', 'ralph', 'reed', 'rishi', 'rocko',
    'tom', 'trinoids', 'whisper', 'wobble', 'zarvox',
  };
  static const Set<String> _female = {
    'allison', 'ava', 'carmit', 'catherine', 'flo', 'fiona', 'grandma', 'joelle',
    'kate', 'karen', 'kathy', 'martha', 'matilda', 'moira', 'nicky', 'noelle',
    'princess', 'samantha', 'sandy', 'serena', 'shelley', 'siri', 'stephanie',
    'superstar', 'susan', 'tessa', 'victoria', 'zoe',
  };

  static VoiceGender _genderByName(String name) {
    final n = name.toLowerCase().split('(').first.trim();
    final first = n.split(' ').first;
    if (_male.contains(n) || _male.contains(first)) return VoiceGender.male;
    if (_female.contains(n) || _female.contains(first)) return VoiceGender.female;
    return VoiceGender.unknown;
  }

  /// Debug: returns the raw voice maps as the device reports them, so you can
  /// see exactly what keys flutter_tts hands you on a real phone.
  static Future<List<Map<String, dynamic>>> debugDump(FlutterTts tts) async {
    final dynamic raw = await tts.getVoices;
    final out = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final v in raw) {
        if (v is Map) out.add(Map<String, dynamic>.from(v));
      }
    }
    return out;
  }
}
