# 本機建置網頁版(帶上雲端 App 金鑰)。金鑰在 ~/.jujenzao_cloud.json,不進 Git。
# 用法: .\build_web_local.ps1        → build\web ;之後用任一靜態伺服器開 build\web 檢查
$c = Get-Content (Join-Path $env:USERPROFILE '.jujenzao_cloud.json') -Raw | ConvertFrom-Json
flutter build web --release "--dart-define=APP_KEY=$($c.app_key)"
