/// 雲端(Cloudflare R2 + 接收 Worker)與 Google 登入設定。
///
/// 員工用 Google 帳號登入,Worker 驗證登入並查名單,所以 App 裡沒有任何金鑰。
/// [workerUrl] 預設是正式 Worker;本機測試用 `--dart-define=WORKER_URL=...`
/// 改指向測試用 Worker。
class CloudConfig {
  static const String workerUrl = String.fromEnvironment(
    'WORKER_URL',
    defaultValue: 'https://jujenzao-daily.ludoufu42.workers.dev',
  );

  /// 貝塔版(`--dart-define=BETA=true`):多一個「模擬時鐘」面板,可以把日期
  /// 調成專案期間的任何一天、一鍵自動跑完整個專案的日報。正式版沒有。
  static const bool isBeta = bool.fromEnvironment('BETA');

  /// OAuth 用戶端 ID(網頁應用程式)。不是機密。
  static const String googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue:
        '1087336903542-nal4ieov3uib32sir6ptj3h9eh7eehc2.apps.googleusercontent.com',
  );
}
