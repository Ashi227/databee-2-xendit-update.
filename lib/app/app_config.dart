class AppConfig {
  static const demoMode = bool.fromEnvironment(
    'DEMO_MODE',
    defaultValue: false,
  );

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://yfaxdqubfuvbyvllyfvx.supabase.co',
  );
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_NoakLfayAi3X7trZ9kN47w_WfTAJDtG',
  );

  static bool get isConfigured =>
      !demoMode &&
      supabaseUrl.startsWith('https://') &&
      supabasePublishableKey.isNotEmpty;
}
