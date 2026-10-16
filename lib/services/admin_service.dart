import 'dart:math';
import '../supabase_config.dart';

class CoachCode {
  final String code;
  final String? label;
  final String? claimedBy;
  final String? claimedAt;
  final String? claimedEmail;

  CoachCode({
    required this.code,
    this.label,
    this.claimedBy,
    this.claimedAt,
    this.claimedEmail,
  });

  bool get isClaimed => claimedBy != null;

  factory CoachCode.fromMap(Map<String, dynamic> map, {String? claimedEmail}) {
    return CoachCode(
      code: map['code'] ?? '',
      label: map['label'],
      claimedBy: map['claimed_by']?.toString(),
      claimedAt: map['claimed_at'],
      claimedEmail: claimedEmail,
    );
  }
}

/// Admin-only operations. Every call here is additionally gated by RLS, so a
/// non-admin reaching this code gets an empty list or a policy error rather
/// than another coach's data.
class AdminService {
  /// Ambiguous characters (O/0, I/1) are left out — these get read aloud and
  /// typed by hand.
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static String generateCoachCode() {
    final rnd = Random.secure();
    final body = List.generate(6, (_) => _alphabet[rnd.nextInt(_alphabet.length)]).join();
    return 'C-$body';
  }

  static Future<List<CoachCode>> loadCoachCodes() async {
    final data = await supabase
        .from('coach_codes')
        .select()
        .order('created_at', ascending: false);
    final rows = (data as List).cast<Map<String, dynamic>>();

    // claimed_by points at auth.users, which PostgREST cannot embed from here,
    // so resolve the emails through profiles in one extra round trip.
    final claimedIds =
        rows.map((r) => r['claimed_by']?.toString()).whereType<String>().toSet().toList();
    final emailById = <String, String>{};
    if (claimedIds.isNotEmpty) {
      final profiles =
          await supabase.from('profiles').select('id, email').inFilter('id', claimedIds);
      for (final p in (profiles as List)) {
        emailById[p['id'].toString()] = p['email'] ?? '';
      }
    }

    return rows
        .map((r) => CoachCode.fromMap(r, claimedEmail: emailById[r['claimed_by']?.toString()]))
        .toList();
  }

  static Future<CoachCode> createCoachCode({String? label}) async {
    final uid = supabase.auth.currentUser?.id;
    // Collisions are vanishingly unlikely, but a duplicate primary key would
    // surface as an opaque error — retry a few times instead.
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = generateCoachCode();
      try {
        final data = await supabase.from('coach_codes').insert({
          'code': code,
          'label': (label == null || label.trim().isEmpty) ? null : label.trim(),
          'created_by': uid,
        }).select();
        return CoachCode.fromMap((data as List).first);
      } catch (e) {
        if (!e.toString().contains('duplicate')) rethrow;
      }
    }
    throw Exception('Could not generate a unique coach code. Please try again.');
  }

  /// Deletes a coach code. If it was already redeemed, this also revokes that
  /// coach's access immediately (demotes their role, so the next live check —
  /// or their next launch — locks them out) rather than merely tidying up the
  /// code list while leaving them able to keep working.
  static Future<CoachCodeDeletion> deleteCoachCode(String code) async {
    final result = await supabase.rpc('delete_coach_code', params: {'p_code': code});
    if (result is Map && result['ok'] != true) {
      throw Exception(result['error']?.toString() ?? 'Could not delete that code.');
    }
    final map = (result as Map).cast<String, dynamic>();
    return CoachCodeDeletion(demotedACoach: map['demoted'] == true);
  }

  /// Coaches who have redeemed a code, with the size of their roster.
  static Future<List<Coach>> loadCoaches() async {
    final data = await supabase
        .from('profiles')
        .select('id, email, full_name, activated_at, shares_library')
        .eq('role', 'coach')
        .order('activated_at', ascending: false);
    final rows = (data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return [];

    // Admins can see every trainee, so a single query covers all coaches.
    final trainees = await supabase.from('trainees').select('coach_id');
    final counts = <String, int>{};
    for (final t in (trainees as List)) {
      final id = t['coach_id']?.toString();
      if (id != null) counts[id] = (counts[id] ?? 0) + 1;
    }

    return rows
        .map((r) => Coach.fromMap(r, traineeCount: counts[r['id'].toString()] ?? 0))
        .toList();
  }

  /// Grants or revokes a coach's view of the admin-authored shared library.
  /// Their own private exercises are never affected — this only changes what
  /// they see, never what they own.
  static Future<void> setCoachLibraryAccess(String coachId, bool canSee) async {
    await supabase
        .from('profiles')
        .update({'shares_library': canSee}).eq('id', coachId);
  }

  /// Revokes a coach's access. Their trainees, programs and private library
  /// move to the admin — deleting the account instead would cascade and take
  /// real trainee records with it — and the code they redeemed is destroyed so
  /// it cannot be reused to get back in.
  static Future<CoachRemoval> removeCoach(String userId) async {
    final result = await supabase.rpc('remove_coach', params: {'p_user_id': userId});
    if (result is Map && result['ok'] != true) {
      throw Exception(result['error']?.toString() ?? 'Could not remove that coach.');
    }
    final map = (result as Map).cast<String, dynamic>();
    return CoachRemoval(
      trainees: (map['trainees'] as num?)?.toInt() ?? 0,
      programs: (map['programs'] as num?)?.toInt() ?? 0,
      library: (map['library'] as num?)?.toInt() ?? 0,
    );
  }
}

class CoachCodeDeletion {
  final bool demotedACoach;
  CoachCodeDeletion({required this.demotedACoach});
}

class Coach {
  final String id;
  final String email;
  final String? fullName;
  final String? activatedAt;
  final int traineeCount;

  /// Whether this coach can see the admin-authored shared exercise library.
  /// Admin-controlled; defaults to true so a newly claimed coach code starts
  /// with the library visible.
  final bool sharesLibrary;

  Coach({
    required this.id,
    required this.email,
    this.fullName,
    this.activatedAt,
    this.traineeCount = 0,
    this.sharesLibrary = false,
  });

  factory Coach.fromMap(Map<String, dynamic> map, {int traineeCount = 0}) {
    return Coach(
      id: map['id'].toString(),
      email: map['email'] ?? '',
      fullName: map['full_name'],
      activatedAt: map['activated_at'],
      traineeCount: traineeCount,
      sharesLibrary: map['shares_library'] == true,
    );
  }

  String get displayName =>
      (fullName != null && fullName!.trim().isNotEmpty) ? fullName! : email;
}

/// What moved to the admin when a coach was removed.
class CoachRemoval {
  final int trainees;
  final int programs;
  final int library;
  CoachRemoval({required this.trainees, required this.programs, required this.library});
}
