# Run from a terminal outside the checkout after closing editors/build tools.
[CmdletBinding(SupportsShouldProcess)]
param()
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath (Split-Path $PSScriptRoot -Parent)).Path
$parent = Split-Path $source -Parent
$target = [IO.Path]::GetFullPath((Join-Path $parent 'chatstudio'))
if ($source -eq $target) { Write-Output 'Workspace is already named chatstudio.'; return }
if (!(Test-Path -LiteralPath (Join-Path $source '.git') -PathType Container)) {
  throw 'Only a standalone Git checkout can be renamed by this script.'
}
if ((Get-Item -LiteralPath $source).Attributes -band [IO.FileAttributes]::ReparsePoint) {
  throw 'Refusing to rename a junction or symlink.'
}
# Check both resolved absolute boundaries; never merge or overwrite a sibling.
if ((Split-Path $target -Parent) -ne $parent -or (Split-Path $target -Leaf) -ne 'chatstudio' -or
    (Test-Path -LiteralPath $target)) {
  throw 'Target must be the unoccupied chatstudio sibling of this checkout.'
}
if ($PSCmdlet.ShouldProcess($source, "Rename checkout to $target")) {
  Set-Location -LiteralPath $parent
  try {
    Move-Item -LiteralPath $source -Destination $target
  } catch {
    throw "Workspace rename failed. Close editors, Codex sessions, Gradle and other processes using the checkout, then retry. No forced process termination is performed. $($_.Exception.Message)"
  }
  Write-Output "Workspace moved to $target. Reopen it, run flutter clean and flutter pub get, then rebuild. Check any custom absolute signing paths."
}
