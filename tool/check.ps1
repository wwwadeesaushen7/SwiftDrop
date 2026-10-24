$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '..')
try {
  flutter pub get --enforce-lockfile
  if ($LASTEXITCODE) { throw 'Dependency resolution failed' }
  dart format lib test integration_test tool
  if ($LASTEXITCODE) { throw 'Formatting failed' }
  flutter analyze
  if ($LASTEXITCODE) { throw 'Analysis failed' }
  flutter test --dart-define=SWIFTDROP_TEST=true --reporter expanded
  if ($LASTEXITCODE) { throw 'Tests failed' }
} finally { Pop-Location }
