import 'package:cadence/config/supabase_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default Android Studio build has Supabase client configuration', () {
    expect(SupabaseConfig.isConfigured, isTrue);
    expect(SupabaseConfig.projectUrl, startsWith('https://'));
    expect(SupabaseConfig.publishableKey, startsWith('sb_publishable_'));
  });
}
