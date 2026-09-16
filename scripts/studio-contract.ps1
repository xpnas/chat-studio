param(
  [Parameter(Mandatory=$true)][string]$StudioPath,
  [string]$Flutter = 'flutter'
)
# Disposable Studio contract test. Never points at a production DB/profile.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$studio = (Resolve-Path -LiteralPath $StudioPath).Path
$expected = 'b44c74318fe5a0a1f3aed29d5095393964fc3d62'
if ((git -C $studio rev-parse HEAD) -ne $expected) { throw 'Wrong Studio revision' }
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
  $node = (Get-Command node).Source
  $provider = Start-Process -FilePath $node -ArgumentList 'tools/mock-provider/server.mjs' -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $state 'provider.log') -RedirectStandardError (Join-Path $state 'provider-error.log')
  $oldHome = $env:HOME; $oldProfile = $env:USERPROFILE
  try {
    $env:HOME = Join-Path $state 'home'; $env:USERPROFILE = $env:HOME
    $service = Start-Process -FilePath $node -ArgumentList '-r','ts-node/register','packages/server/src/index.ts' -WorkingDirectory $studio -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $state 'studio.log') -RedirectStandardError (Join-Path $state 'studio-error.log')
  } finally { $env:HOME = $oldHome; $env:USERPROFILE = $oldProfile }
  Push-Location $root
  try {
    & $node tools/mock-provider/bootstrap.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Studio bootstrap failed; inspect private diagnostic logs' }
    & $Flutter test test/live_contract_test.dart --reporter expanded
    if ($LASTEXITCODE -ne 0) { throw 'Studio contract tests failed' }
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
