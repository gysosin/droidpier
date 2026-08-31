$ErrorActionPreference = 'Stop'
$repositoryDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$flutterBin = if ($env:FLUTTER_BIN) { $env:FLUTTER_BIN } else { 'flutter' }
$version = & python (Join-Path $PSScriptRoot 'version.py')
if ($LASTEXITCODE -ne 0) { throw 'Version validation failed.' }
$code = & python (Join-Path $PSScriptRoot 'version.py') androidVersionCode
if ($LASTEXITCODE -ne 0) { throw 'Version validation failed.' }
if (-not $env:DROIDPIER_ANDROID_PAYLOAD_DIR) {
  & python (Join-Path $PSScriptRoot 'build_android.py')
  if ($LASTEXITCODE -ne 0) { throw 'Android release build failed.' }
}
Push-Location (Join-Path $repositoryDir 'apps/desktop')
try {
  & $flutterBin pub get
  if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
  & $flutterBin analyze
  if ($LASTEXITCODE -ne 0) { throw 'Analysis failed.' }
  & $flutterBin test --exclude-tags golden
  if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
  & $flutterBin build windows --release --no-tree-shake-icons "--build-name=$version" "--build-number=$code"
  if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
} finally { Pop-Location }
& python (Join-Path $PSScriptRoot 'package_native.py') windows
if ($LASTEXITCODE -ne 0) { throw 'Windows packaging failed.' }
