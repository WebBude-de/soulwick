<#
.SYNOPSIS
  Exports Soulwick for Windows (and Linux) into builds/<env>/<version>/ and zips each build (MP4).

.DESCRIPTION
  - env (development | production) is written into online/environment.cfg for the export and the
    file is restored afterwards; it selects API and relay addresses (OnlineConfig, platform P-018).
  - version must equal application/config/version in project.godot (the game reports that one).
  - The dev key is never packed; testers put it into user://online.cfg (docs/MULTIPLAYER.md §3d).
  - Stops before exporting when the export templates of this Godot version are missing.
  - After the Windows export the exe is started once headless (-- offline) to check that it boots.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/export_build.ps1
  powershell -ExecutionPolicy Bypass -File tools/export_build.ps1 -Env production -Version 0.9.0 -Platforms windows
#>
param(
	[Alias("Env")]
	[ValidateSet("development", "production")]
	[string]$Environment = "development",
	[string]$Version = "",
	[ValidateSet("windows", "linux")]
	[string[]]$Platforms = @("windows", "linux"),
	[string]$Godot = $(if ($env:GODOT) { $env:GODOT } else { "C:\Tools\Godot\Godot_v4.7.2-stable_win64.exe" }),
	[string]$TemplateVersion = "4.7.2.stable",
	[switch]$SkipBootTest
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$EnvFile = Join-Path $Root "online\environment.cfg"

$Targets = @{
	windows = @{ Preset = "Windows Desktop"; Binary = "Soulwick.exe"; Template = "windows_release_x86_64.exe" }
	linux   = @{ Preset = "Linux"; Binary = "Soulwick.x86_64"; Template = "linux_release.x86_64" }
}

# --- Version ---
$match = Select-String -Path (Join-Path $Root "project.godot") -Pattern '^config/version="([^"]*)"'
if (-not $match) { throw "project.godot has no application/config/version." }
$ProjectVersion = $match.Matches[0].Groups[1].Value
if (-not $Version) { $Version = $ProjectVersion }
if ($Version -ne $ProjectVersion) {
	throw "Version $Version differs from project.godot ($ProjectVersion). Set application/config/version first."
}

# --- Godot and export templates ---
if (-not (Test-Path $Godot)) { throw "Godot not found: $Godot (parameter -Godot or env GODOT)." }
$TemplateDir = Join-Path $env:APPDATA "Godot\export_templates\$TemplateVersion"
$missing = @()
foreach ($platform in $Platforms) {
	$file = Join-Path $TemplateDir $Targets[$platform].Template
	if (-not (Test-Path $file)) { $missing += $file }
}
if ($missing.Count -gt 0) {
	Write-Host "Export templates for Godot $TemplateVersion are missing:" -ForegroundColor Yellow
	$missing | ForEach-Object { Write-Host "  $_" }
	Write-Host "Install them once: Godot editor -> Editor -> Manage Export Templates -> Download and Install"
	Write-Host "(or 'Install from File' with Godot_v4.7.2-stable_export_templates.tpz from godotengine.org)."
	exit 2
}

# --- Export ---
$OutDir = Join-Path $Root "builds\$Environment\$Version"
New-Item -ItemType Directory -Force $OutDir | Out-Null
# The editor must not import the builds folder.
$GdIgnore = Join-Path $Root "builds\.gdignore"
if (-not (Test-Path $GdIgnore)) { New-Item -ItemType File $GdIgnore | Out-Null }

$OriginalEnv = [System.IO.File]::ReadAllText($EnvFile)
$Readme = [System.IO.File]::ReadAllText((Join-Path $Root "tools\build_readme.txt")).Replace("{version}", $Version).Replace("{env}", $Environment)
$Zips = @()
try {
	$patched = [regex]::Replace($OriginalEnv, '(?m)^env\s*=.*$', "env=`"$Environment`"")
	[System.IO.File]::WriteAllText($EnvFile, $patched, (New-Object System.Text.UTF8Encoding($false)))
	foreach ($platform in $Platforms) {
		$target = $Targets[$platform]
		$PlatformDir = Join-Path $OutDir $platform
		if (Test-Path $PlatformDir) { Remove-Item -Recurse -Force $PlatformDir }
		New-Item -ItemType Directory -Force $PlatformDir | Out-Null
		$Binary = Join-Path $PlatformDir $target.Binary
		Write-Host "Exporting $($target.Preset) ($Environment, $Version) -> $Binary"
		& $Godot --headless --path $Root --export-release $target.Preset $Binary
		if ($LASTEXITCODE -ne 0 -or -not (Test-Path $Binary)) { throw "Export of $($target.Preset) failed (exit $LASTEXITCODE)." }
		[System.IO.File]::WriteAllText((Join-Path $PlatformDir "LIESMICH.txt"), $Readme.Replace("`n", "`r`n"), (New-Object System.Text.UTF8Encoding($false)))

		if ($platform -eq "windows" -and -not $SkipBootTest) {
			# Boot check with its own user folder, so no settings or logs land in the real one.
			$BootData = Join-Path $OutDir ".boot_userdata"
			$OldAppData = $env:APPDATA
			try {
				$env:APPDATA = $BootData
				$bootLog = & $Binary --headless --quit-after 300 -- offline 2>&1 | Out-String
				$bootExit = $LASTEXITCODE
				Write-Host $bootLog
			} finally {
				$env:APPDATA = $OldAppData
				if (Test-Path $BootData) { Remove-Item -Recurse -Force $BootData }
			}
			if ($bootExit -ne 0 -or $bootLog -match "SCRIPT ERROR|Parse Error|Failed to load") {
				throw "The exported exe did not boot cleanly (exit $bootExit, see the log above)."
			}
			Write-Host "Boot check passed."
		}

		$Zip = Join-Path $OutDir "Soulwick-$Version-$Environment-$platform.zip"
		if (Test-Path $Zip) { Remove-Item -Force $Zip }
		Compress-Archive -Path (Join-Path $PlatformDir "*") -DestinationPath $Zip
		$Zips += $Zip
	}
} finally {
	[System.IO.File]::WriteAllText($EnvFile, $OriginalEnv, (New-Object System.Text.UTF8Encoding($false)))
}

Write-Host "Done:" -ForegroundColor Green
$Zips | ForEach-Object { Write-Host "  $_" }
