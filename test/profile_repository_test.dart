import 'package:cadence/data/profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile maps nullable account fields', () {
    final profile = UserProfile.fromJson({
      'id': 'user-1',
      'display_name': 'Carmen',
      'avatar_url': null,
    });
    expect(profile.id, 'user-1');
    expect(profile.displayName, 'Carmen');
    expect(profile.avatarUrl, isNull);
  });
}
