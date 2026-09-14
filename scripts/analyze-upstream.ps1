param([string]$Upstream = (Join-Path (Split-Path $PSScriptRoot -Parent) '../hermes-studio-v1.0.3'))
$ErrorActionPreference = 'Stop'
$commit = 'b44c74318fe5a0a1f3aed29d5095393964fc3d62'
if (-not (Test-Path -LiteralPath $Upstream)) {
  git clone --branch v1.0.3 --depth 1 https://github.com/EKKOLearnAI/hermes-studio.git $Upstream
  if ($LASTEXITCODE -ne 0) { throw 'Clone failed' }
}
$actual = git -C $Upstream rev-parse HEAD
if ($actual -ne $commit) { throw "Expected v1.0.3 commit $commit; got $actual. Existing checkout not modified." }
$root = (Resolve-Path -LiteralPath $Upstream).Path
$output = Join-Path (Split-Path $PSScriptRoot -Parent) 'docs/analysis'
npm exec --yes --package=@lzehrung/codegraph@2.3.26 -- codegraph orient --root $root --budget small --json | Set-Content (Join-Path $output 'codegraph-orient.json') -Encoding utf8
if ($LASTEXITCODE -ne 0) { throw 'CodeGraph orient failed' }
npm exec --yes --package=@lzehrung/codegraph@2.3.26 -- codegraph explore 'appLogin ChatRunSocket getAvailable' --root $root --json | Set-Content (Join-Path $output 'codegraph-auth-chat.json') -Encoding utf8
if ($LASTEXITCODE -ne 0) { throw 'CodeGraph explore failed' }
