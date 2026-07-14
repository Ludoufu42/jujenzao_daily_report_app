/// Fill in [appKey] once you've created a Dropbox app at
/// https://www.dropbox.com/developers/apps (Scoped access, "App folder"
/// permission is enough — the app only ever writes into its own
/// `Apps/<app name>/` folder, never the user's whole Dropbox).
///
/// [redirectUri] must use the same custom scheme registered as
/// `appAuthRedirectScheme` in android/app/build.gradle.kts.
class DropboxConfig {
  static const String appKey = '';
  static const String redirectUri =
      'com.jujenzao.jujenzao_daily_report_app://oauth2redirect';

  static bool get isConfigured => appKey.isNotEmpty;
}
