import 'package:flutter/foundation.dart' show kIsWeb;

/// Fill in [appKey] once you've created a Dropbox app at
/// https://www.dropbox.com/developers/apps (Scoped access, "App folder"
/// permission is enough — the app only ever writes into its own
/// `Apps/<app name>/` folder, never the user's whole Dropbox).
///
/// On web, `flutter_web_auth_2` needs a real HTTPS redirect that serves
/// `web/auth.html` (see that file) rather than a custom URI scheme — this
/// exact URL must also be added under "Redirect URIs" in the Dropbox App
/// Console. On native platforms it uses the custom scheme registered as
/// `appAuthRedirectScheme` in android/app/build.gradle.kts instead.
class DropboxConfig {
  static const String appKey = 'l0306mul9z8extv';

  static String get redirectUri => kIsWeb
      ? 'https://ludoufu42.github.io/jujenzao_daily_report_app/auth.html'
      : 'com.jujenzao.jujenzao_daily_report_app://oauth2redirect';

  static bool get isConfigured => appKey.isNotEmpty;
}
