param([string]$IsccPath = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe")
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Push-Location (Join-Path $PSScriptRoot '..')
try {
  $source = Get-Content pubspec.yaml -Raw
  $match = [regex]::Match($source, '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$')
  if (!$match.Success) { throw 'pubspec.yaml must declare major.minor.patch+build.' }
  $version = "$($match.Groups[1].Value).$($match.Groups[2].Value).$($match.Groups[3].Value)"
  $parts = 1..4 | ForEach-Object { [int]$match.Groups[$_].Value }
  $recipe = Get-Content packaging/swiftdrop.iss -Raw
  if ($recipe -notmatch "(?m)^#define AppVersion `"$([regex]::Escape($version))`"\s*$") {
    throw "Installer recipe does not match pubspec version $version."
  }
  $exe = Get-Item 'build/windows/x64/runner/Release/swiftdrop.exe'
  $info = $exe.VersionInfo
  $actual = @($info.FileMajorPart, $info.FileMinorPart, $info.FileBuildPart, $info.FilePrivatePart)
  if (($actual -join '.') -ne ($parts -join '.')) {
    throw "Compiled EXE version $($actual -join '.') does not match source $($parts -join '.'). Rebuild Windows first."
  }
  if (!(Test-Path $IsccPath)) { throw 'Inno Setup 6 compiler was not found.' }
  $commit = (& git rev-parse HEAD).Trim()
  if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]{40}$') { throw 'Cannot determine source commit.' }
  $name = "SwiftDrop-$version-windows-x64-setup.exe"
  $installer = Join-Path (Get-Location) "build/installer/$name"
  if (Test-Path $installer) { Remove-Item $installer }
  & $IsccPath packaging/swiftdrop.iss
  if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed.' }
  $built = Get-Item $installer
  $setupVersion = "$($built.VersionInfo.FileMajorPart).$($built.VersionInfo.FileMinorPart).$($built.VersionInfo.FileBuildPart)"
  if ($setupVersion -ne $version) { throw "Installer embeds version $setupVersion; expected $version." }
  $hash = (Get-FileHash $installer -Algorithm SHA256).Hash.ToLowerInvariant()
  $metadata = [ordered]@{
    version = $version
    build_number = $parts[3]
    source_commit = $commit
    application_version = $actual -join '.'
    installer_version = $setupVersion
    installer_filename = $name
    installer_sha256 = $hash
    installer_bytes = $built.Length
  }
  $utf8 = [System.Text.UTF8Encoding]::new($false)
  [IO.File]::WriteAllText((Join-Path (Get-Location) 'build/installer/BUILD-INFO.json'), ($metadata | ConvertTo-Json) + "`n", $utf8)
  [IO.File]::WriteAllText((Join-Path (Get-Location) 'build/installer/SHA256SUMS.txt'), "$hash  $name`n", $utf8)
  [IO.File]::WriteAllText((Join-Path $exe.DirectoryName 'VERSION.txt'), "SwiftDrop $version+$($parts[3])`nSource commit: $commit`n", $utf8)
  $artifact = "SwiftDrop-$version-Windows-installer-$($commit.Substring(0, 8))"
  if ($env:GITHUB_OUTPUT) {
    Add-Content $env:GITHUB_OUTPUT "version=$version"
    Add-Content $env:GITHUB_OUTPUT "artifact=$artifact"
  }
  Write-Output "Verified $name ($($built.Length) bytes), SHA-256 $hash, source $commit"
} finally { Pop-Location }
