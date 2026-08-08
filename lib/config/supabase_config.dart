class SupabaseConfig {
  static const projectUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://gqoofslgfyejaeeoofpg.supabase.co',
  );
  // A Supabase publishable key is intentionally safe for public mobile
  // clients. A build define can still override it for staging/production.
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_OytUelkiHLiDxmzu-7dUKQ_n_P-ugoq',
  );
  static const redirectUrl = 'weekplanner://login-callback';

  static bool get isConfigured =>
      projectUrl.startsWith('https://') && publishableKey.trim().isNotEmpty;
}
