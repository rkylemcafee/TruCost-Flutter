// lib/survey/survey_repository.dart
//
// Route surveys, read from the same Supabase the web app writes to. There is no
// separate mobile schema and no sync layer: route_surveys, survey_points and
// survey_photos are the same tables, with the same row-level security, so a
// survey built at a desk opens in the truck and a photograph taken in the truck
// is in the report before anyone gets back.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

class SurveyRepository {
  final _db = Supabase.instance.client;

  /// Surveys this tenant can see, newest first. RLS does the scoping.
  Future<List<Map<String, dynamic>>> surveys() async {
    final rows = await _db
        .from('route_surveys')
        .select()
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>?> survey(String id) async {
    final row = await _db.from('route_surveys').select().eq('id', id).maybeSingle();
    return row;
  }

  /// The turns, in driving order.
  Future<List<Map<String, dynamic>>> points(String surveyId) async {
    final rows = await _db
        .from('survey_points')
        .select()
        .eq('survey_id', surveyId)
        .order('seq');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> photos(String surveyId) async {
    final rows = await _db
        .from('survey_photos')
        .select()
        .eq('survey_id', surveyId)
        .order('sort_order');
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Structures found on the route, with whatever was decided about each.
  Future<List<Map<String, dynamic>>> structures(String surveyId) async {
    final rows = await _db
        .from('survey_structures')
        .select()
        .eq('survey_id', surveyId)
        .order('seq');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> updatePoint(String id, Map<String, dynamic> patch) async {
    await _db.from('survey_points').update(patch).eq('id', id);
  }

  Future<void> updateStructure(String id, Map<String, dynamic> patch) async {
    await _db.from('survey_structures').update(patch).eq('id', id);
  }

  /// Put a photograph in the bucket the web app reads from, and record it.
  ///
  /// Position comes from the handset rather than the file: the picture is being
  /// taken here, now, so the phone knows where "here" is more reliably than the
  /// camera will admit to.
  Future<void> addPhoto({
    required String surveyId,
    required String? pointId,
    required File file,
    double? lat,
    double? lng,
    String? caption,
  }) async {
    final name = '${DateTime.now().millisecondsSinceEpoch}-${file.uri.pathSegments.last}';
    final path = 'surveys/$surveyId/$name';

    await _db.storage.from('tenant-assets').upload(path, file);

    // sort_order is an ordinal. A millisecond timestamp overflows the column,
    // which is how the web app managed to never upload a photo at all.
    final existing = await _db
        .from('survey_photos')
        .select('sort_order')
        .eq('survey_id', surveyId)
        .order('sort_order', ascending: false)
        .limit(1);
    final next = existing.isEmpty ? 1 : ((existing.first['sort_order'] as int?) ?? 0) + 1;

    await _db.from('survey_photos').insert({
      'survey_id': surveyId,
      'point_id': pointId,
      'storage_path': path,
      'exif_lat': lat,
      'exif_lng': lng,
      'taken_at': DateTime.now().toUtc().toIso8601String(),
      'caption': caption,
      'sort_order': next,
    });
  }

  Future<void> deletePhoto(String id) async {
    await _db.from('survey_photos').delete().eq('id', id);
  }

  /// Load dimensions, names, dates — the Load & Route tab's fields.
  Future<void> updateSurvey(String id, Map<String, dynamic> patch) async {
    await _db.from('route_surveys').update({
      ...patch,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  // ── Documents ────────────────────────────────────────────────────────────
  //
  // The paperwork about the whole move — the state's survey, the permit, the
  // reports made from it — as opposed to photos taken at a point. Same
  // survey_documents table the web writes, so a report made on the phone is
  // on the desk's Reports tab too.

  /// Everything filed against the survey, newest first.
  Future<List<Map<String, dynamic>>> documents(String surveyId) async {
    final rows = await _db
        .from('survey_documents')
        .select()
        .eq('survey_id', surveyId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Store a file and record it. The stored name keeps the original inside a
  /// folder for the survey and kind, with a timestamp so two "map.png"s on
  /// one job are two maps rather than one.
  Future<Map<String, dynamic>> uploadDocument({
    required String surveyId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String kind,
    String caption = '',
  }) async {
    final safe = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path = 'surveys/$surveyId/$kind/${DateTime.now().millisecondsSinceEpoch}-$safe';
    await _db.storage.from('tenant-assets').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
    try {
      return await _db
          .from('survey_documents')
          .insert({
            'survey_id': surveyId,
            'kind': kind,
            'storage_path': path,
            'file_name': fileName,
            'mime_type': mimeType,
            'byte_size': bytes.length,
            'caption': caption.isEmpty ? null : caption,
          })
          .select()
          .single();
    } catch (_) {
      // The row is what makes the file findable; without it the upload is
      // litter in a bucket nobody looks in.
      await _db.storage.from('tenant-assets').remove([path]);
      rethrow;
    }
  }

  /// Row first, file second: an orphaned file is untidy, a row pointing at
  /// nothing looks like a document until somebody opens it.
  Future<void> deleteDocument(Map<String, dynamic> doc) async {
    await _db.from('survey_documents').delete().eq('id', doc['id']);
    try {
      await _db.storage.from('tenant-assets').remove([doc['storage_path']]);
    } catch (_) {}
  }

  String publicUrl(String storagePath) =>
      _db.storage.from('tenant-assets').getPublicUrl(storagePath);
}

/// Straight-line miles between two coordinates.
double milesApart(double la1, double ln1, double la2, double ln2) {
  const r = 3958.7613;
  const p = 0.017453292519943295;
  final dLa = (la2 - la1) * p;
  final dLo = (ln2 - ln1) * p;
  final h = (1 - _cos(dLa)) / 2 +
      _cos(la1 * p) * _cos(la2 * p) * (1 - _cos(dLo)) / 2;
  return 2 * r * _asin(_sqrt(h));
}

double _cos(double x) => math.cos(x);
double _asin(double x) => math.asin(x);
double _sqrt(double x) => math.sqrt(x);

