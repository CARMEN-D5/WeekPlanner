import 'package:supabase_flutter/supabase_flutter.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    required this.displayName,
    required this.avatarUrl,
  });

  final String id;
  final String? displayName;
  final String? avatarUrl;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        displayName: json['display_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
      );
}

/// Account-only repository. Planner data remains local until Cloud Sync.
class ProfileRepository {
  ProfileRepository(this._client);
  final SupabaseClient _client;

  Future<UserProfile?> fetch(String userId) async {
    final row = await _client.from('profiles').select().eq('id', userId).maybeSingle();
    return row == null ? null : UserProfile.fromJson(row);
  }

  Future<UserProfile> ensureFor(User user) async {
    final existing = await fetch(user.id);
    if (existing != null) return existing;
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final name = (metadata['full_name'] ?? metadata['name'] ??
            user.email?.split('@').first)
        ?.toString();
    final avatar = (metadata['avatar_url'] ?? metadata['picture'])?.toString();
    final row = await _client
        .from('profiles')
        .upsert({
          'id': user.id,
          'display_name': name,
          'avatar_url': avatar,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'id')
        .select()
        .single();
    return UserProfile.fromJson(row);
  }
}
