param(
  [Parameter(Mandatory=$true)][string]$StudioPath,
  [string]$Flutter = 'flutter',
  [ValidateSet('legacy', 'stable', 'preview-agents')][string]$Baseline = 'legacy',
  [switch]$NativeCodex,
  [string]$AndroidDevice = '',
  [string[]]$TestFiles = @('test/live_contract_test.dart', 'test/plugin_live_contract_test.dart', 'test/session_tasks_live_contract_test.dart', 'test/group_selection_live_contract_test.dart', 'test/person_live_contract_test.dart', 'test/person_cache_live_contract_test.dart'),
  [switch]$PreflightOnly
)
# Disposable Studio contract test. Never points at a production DB/profile.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$studio = (Resolve-Path -LiteralPath $StudioPath).Path
$node = (Get-Command node).Source
$baselineJson = & $node (Join-Path $root 'tools/studio-baselines.mjs') verify $Baseline $studio
if ($LASTEXITCODE -ne 0) { throw 'Studio baseline verification failed' }
$selectedBaseline = $baselineJson | ConvertFrom-Json
if ($PreflightOnly) { Write-Output $baselineJson; exit 0 }
if (!(Test-Path -LiteralPath (Join-Path $studio 'node_modules'))) { throw 'Run npm ci in Studio first' }
foreach ($port in @(18647, 18648)) {
  $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
  try { $listener.Start() } finally { $listener.Stop() }
}
$state = Join-Path $root ('.local/contract-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $state | Out-Null
foreach ($name in @('hermes', 'studio', 'database', 'home', 'workspace')) {
  New-Item -ItemType Directory -Path (Join-Path $state $name) | Out-Null
}
$bytes = New-Object byte[] 24
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
$password = [Convert]::ToBase64String($bytes)
$settings = @{
  CHATSTUDIO_TEST_MEDIA = '1'; CHATSTUDIO_TEST_SERVER = 'http://127.0.0.1:18647'; CHATSTUDIO_TEST_PASSWORD = $password
  CHATSTUDIO_TEST_BASELINE = $Baseline; CHATSTUDIO_TEST_SHA = $selectedBaseline.sha
  MOCK_PROVIDER_PORT = '18648'
  CHATSTUDIO_TEST_NATIVE_CODEX = $(if ($NativeCodex) {'1'} else {'0'})
  WORKSPACE_BASE = (Join-Path $state 'workspace')
  HERMES_HOME = (Join-Path $state 'hermes'); HERMES_WEB_UI_HOME = (Join-Path $state 'studio')
  HERMES_WEBUI_STATE_DIR = (Join-Path $state 'studio'); NODE_ENV = 'test'
  HERMES_WEB_UI_TEST_DB_DIR = (Join-Path $state 'database'); HERMES_RUNTIME_SOURCE = 'none'
  PORT = '18647'; BIND_HOST = '127.0.0.1'; HERMES_LAN_DISCOVERY_ENABLED = 'false'
  HERMES_WEB_UI_DISABLE_GATEWAY_AUTOSTART = '1'; HERMES_WEB_UI_DISABLE_MCP_AUTOINJECT = '1'
  TS_NODE_PROJECT = 'packages/server/tsconfig.json'; TS_NODE_TRANSPILE_ONLY = 'true'
  TS_NODE_COMPILER_OPTIONS = '{"rootDir":"../../"}'
}
$previous = @{}
$provider = $null; $service = $null
try {
  foreach ($name in $settings.Keys) {
    $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    [Environment]::SetEnvironmentVariable($name, $settings[$name], 'Process')
  }
  Copy-Item -LiteralPath (Join-Path $root 'tools/mock-provider/config.yaml') -Destination (Join-Path $state 'hermes/config.yaml')
  $provider = Start-Process -FilePath $node -ArgumentList 'tools/mock-provider/server.mjs' -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $state 'provider.log') -RedirectStandardError (Join-Path $state 'provider-error.log')
  # Child-only HOME isolation leaves the caller and Flutter's caches untouched.
  $childEnvironment = @{ HOME = (Join-Path $state 'home'); USERPROFILE = (Join-Path $state 'home'); CODEX_HOME = (Join-Path $state 'home/.codex') }
  if ($NativeCodex) {
    $nativeHome = Join-Path $state 'home/.codex'
    & $node (Join-Path $root 'tools/mock-provider/native-codex.mjs') $nativeHome
    if ($LASTEXITCODE -ne 0) { throw 'Could not prepare isolated native Codex configuration' }
    $childEnvironment.CODEX_HOME = $nativeHome
    $childEnvironment.CHATSTUDIO_NATIVE_FIXTURE_KEY = 'local-fixture-not-a-secret'
  }
  $service = Start-Process -FilePath $node -ArgumentList '-r','ts-node/register',$selectedBaseline.entrypoint -Environment $childEnvironment -WorkingDirectory $studio -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $state 'studio.log') -RedirectStandardError (Join-Path $state 'studio-error.log')
  Push-Location $root
  try {
    & $node tools/mock-provider/bootstrap.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Studio bootstrap failed; inspect private diagnostic logs' }
    $report = Join-Path $state 'client-results.jsonl'
    & $Flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'Flutter dependencies failed' }
    if ($AndroidDevice) {
      # The temporary file and debug APK contain disposable test credentials.
      # Keep them private alongside the isolated DB and raw diagnostics.
      $defines = Join-Path $state 'android-defines.json'
      @{ CHATSTUDIO_TEST_SERVER=$settings.CHATSTUDIO_TEST_SERVER; CHATSTUDIO_TEST_PASSWORD=$password; CHATSTUDIO_TEST_BASELINE=$Baseline; STUDIO_BOTS='true' } | ConvertTo-Json | Set-Content -LiteralPath $defines -Encoding utf8
      & adb -s $AndroidDevice reverse tcp:18647 tcp:18647
      if ($LASTEXITCODE -ne 0) { throw 'Android test server forwarding failed' }
      try {
        & $Flutter test integration_test/person_live_acceptance_test.dart -d $AndroidDevice "--dart-define-from-file=$defines" --no-pub --reporter json | Out-File -LiteralPath $report -Encoding utf8
        $androidTestExit = $LASTEXITCODE
      } finally {
        & adb -s $AndroidDevice reverse --remove tcp:18647 2>&1 | Out-Null
      }
      if ($androidTestExit -ne 0) { throw 'Android Studio contract tests failed' }
      # Flutter's device runner prints Gradle/install progress on stdout even
      # with the JSON reporter. Retain that raw output, then validate every
      # reporter event with the same strict parser used by host contracts.
      Copy-Item -LiteralPath $report -Destination (Join-Path $state 'android-client-output.log')
      $reportEvents = @(Get-Content -LiteralPath $report | Where-Object { $_.StartsWith('{') })
      $reportEvents | Set-Content -LiteralPath $report -Encoding utf8
    } else {
      # Cache-fault setup owns a second SQLite connection. Run suites serially
      # against this one disposable DB; each suite still tests two live clients.
      & $Flutter test @TestFiles --concurrency=1 --no-pub --reporter json | Out-File -LiteralPath $report -Encoding utf8
    }
    if ($LASTEXITCODE -ne 0) { throw 'Studio contract tests failed' }
    & $node tools/contract-report.mjs $report
    if ($LASTEXITCODE -ne 0) { throw 'Studio contract report invalid or zero tests executed' }
  } finally { Pop-Location }
} finally {
  # Kill only processes launched above and their runtime descendants.
  foreach ($process in @($service, $provider)) {
    if ($null -ne $process -and !$process.HasExited) {
      & taskkill /PID $process.Id /T /F 2>&1 | Out-Null
    }
  }
  foreach ($name in $previous.Keys) {
    [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
  }
  Write-Host "Private diagnostics retained in $state (do not upload)."
}
