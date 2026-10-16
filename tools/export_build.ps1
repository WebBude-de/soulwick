<#
.SYNOPSIS
  Exports Soulwick for Windows (and Linux, macOS, Web, Android) into builds/<env>/<version>/ and zips
  each desktop build (MP4); macOS becomes Soulwick-<version>-<env>-macos.zip (universal Soulwick.app,
  ad-hoc signed, not notarized), Web the folder builds/<env>/<version>/web/ plus its zip, Android
  builds/<env>/<version>/Soulwick-<version>-<env>.apk (CP2/CP7). Same rules as tools/export_build.sh,
  which the release workflow (.github/workflows/release.yml) uses.

.DESCRIPTION
  - env (development | production) is written into online/environment.cfg for the export and the
    file is restored afterwards; it selects API and relay addresses (OnlineConfig, platform P-018).
  - version must equal application/config/version in project.godot (the game reports that one).
  - The dev key is never packed; testers put it into user://online.cfg (docs/MULTIPLAYER.md §3d).
  - Stops before exporting when the export templates of this Godot version are missing.
  - After the Windows export the exe is started once headless (-- offline) to check that it boots.
  - Android (no boot check): needs JDK 17 (-JavaHome / JAVA_HOME) and the Android SDK path in the
    Godot editor settings (docs/MULTIPLAYER.md §3d). Signed with GODOT_ANDROID_KEYSTORE_RELEASE_PATH,
    _USER and _PASSWORD when set; otherwise a development build uses the local debug keystore
    (%APPDATA%\Godot\keystores\debug.keystore, created with keytool if missing). Production needs the
    real upload key. Never put a keystore into the repo. version/code of the "Android" preset is set
    from the version for the export (0.9.0 -> 900) and restored afterwards.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/export_build.ps1
  powershell -ExecutionPolicy Bypass -File tools/export_build.ps1 -Env production -Version 0.9.0 -Platforms windows
  powershell -ExecutionPolicy Bypass -File tools/export_build.ps1 -Env development -Platforms android
#>
param(
	[Alias("Env")]
	[ValidateSet("development", "production")]
	[string]$Environment = "development",
	[string]$Version = "",
	[ValidateSet("windows", "linux", "macos", "web", "android")]
	[string[]]$Platforms = @("windows", "linux"),
	[string]$Godot = $(if ($env:GODOT) { $env:GODOT } else { "C:\Tools\Godot\Godot_v4.7.2-stable_win64.exe" }),
	[string]$TemplateVersion = "4.7.2.stable",
	[string]$JavaHome = $(if ($env:JAVA_HOME) { $env:JAVA_HOME } else { "C:\Program Files\Java\jdk-17.0.5" }),
	[switch]$SkipBootTest
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$EnvFile = Join-Path $Root "online\environment.cfg"
$PresetsFile = Join-Path $Root "export_presets.cfg"
$Utf8 = New-Object System.Text.UTF8Encoding($false)

$Targets = @{
	windows = @{ Preset = "Windows Desktop"; Binary = "Soulwick.exe"; Template = "windows_release_x86_64.exe" }
	linux   = @{ Preset = "Linux"; Binary = "Soulwick.x86_64"; Template = "linux_release.x86_64" }
	macos   = @{ Preset = "macOS"; Binary = ""; Template = "macos.zip" }
	web     = @{ Preset = "Web"; Binary = "index.html"; Template = "web_nothreads_release.zip" }
	android = @{ Preset = "Android"; Binary = ""; Template = "android_release.apk" }
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

# --- Android: JDK, SDK, signing key, version code ---
$AndroidEnvBackup = @{}
if ($Platforms -contains "android") {
	$Keytool = Join-Path $JavaHome "bin\keytool.exe"
	if (-not (Test-Path $Keytool)) { throw "JDK 17 not found: $JavaHome (parameter -JavaHome or env JAVA_HOME)." }
	$SdkHome = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA "Android\Sdk" }
	if (-not (Test-Path (Join-Path $SdkHome "build-tools"))) {
		Write-Host "Android SDK not found: $SdkHome (see docs/MULTIPLAYER.md section 3d: sdkmanager platform-tools, build-tools, platforms)." -ForegroundColor Yellow
		exit 2
	}
	foreach ($name in @("JAVA_HOME", "GODOT_ANDROID_KEYSTORE_RELEASE_PATH", "GODOT_ANDROID_KEYSTORE_RELEASE_USER", "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD")) {
		$AndroidEnvBackup[$name] = [Environment]::GetEnvironmentVariable($name)
	}
	$env:JAVA_HOME = $JavaHome
	if (-not $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH) {
		if ($Environment -eq "production") {
			throw "Production APKs need the real key: set GODOT_ANDROID_KEYSTORE_RELEASE_PATH, _USER and _PASSWORD."
		}
		$DebugKeystore = Join-Path $env:APPDATA "Godot\keystores\debug.keystore"
		if (-not (Test-Path $DebugKeystore)) {
			New-Item -ItemType Directory -Force (Split-Path $DebugKeystore) | Out-Null
			& $Keytool -genkeypair -keystore $DebugKeystore -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US" | Out-Host
			if ($LASTEXITCODE -ne 0) { throw "keytool could not create $DebugKeystore." }
		}
		Write-Host "Signing the APK with the local debug keystore ($DebugKeystore)."
		$env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = $DebugKeystore
		$env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = "androiddebugkey"
		$env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = "android"
	}
}
# 0.9.0 -> 900, 1.2.3 -> 10203: grows with every version, so phones accept the update.
$parts = @(($Version -split '[^0-9]+') | Where-Object { $_ -ne "" } | ForEach-Object { [int]$_ }) + @(0, 0, 0)
$VersionCode = [Math]::Max(1, $parts[0] * 10000 + $parts[1] * 100 + $parts[2])

# --- Export ---
$OutDir = Join-Path $Root "builds\$Environment\$Version"
New-Item -ItemType Directory -Force $OutDir | Out-Null
# The editor must not import the builds folder.
$GdIgnore = Join-Path $Root "builds\.gdignore"
if (-not (Test-Path $GdIgnore)) { New-Item -ItemType File $GdIgnore | Out-Null }

$OriginalEnv = [System.IO.File]::ReadAllText($EnvFile)
$OriginalPresets = [System.IO.File]::ReadAllText($PresetsFile)
$Readme = [System.IO.File]::ReadAllText((Join-Path $Root "tools\build_readme.txt")).Replace("{version}", $Version).Replace("{env}", $Environment)
$Outputs = @()
try {
	$patched = [regex]::Replace($OriginalEnv, '(?m)^env\s*=.*$', "env=`"$Environment`"")
	[System.IO.File]::WriteAllText($EnvFile, $patched, $Utf8)
	foreach ($platform in $Platforms) {
		$target = $Targets[$platform]

		if ($platform -eq "android") {
			# The APK goes straight into the version folder; no boot check (no device needed).
			$Apk = Join-Path $OutDir "Soulwick-$Version-$Environment.apk"
			if (Test-Path $Apk) { Remove-Item -Force $Apk }
			$presets = [regex]::Replace($OriginalPresets, '(?m)^version/code=\d+', "version/code=$VersionCode")
			[System.IO.File]::WriteAllText($PresetsFile, $presets, $Utf8)
			Write-Host "Exporting $($target.Preset) ($Environment, $Version, code $VersionCode) -> $Apk"
			& $Godot --headless --path $Root --export-release $target.Preset $Apk | Out-Host
			if ($LASTEXITCODE -ne 0 -or -not (Test-Path $Apk)) { throw "Export of $($target.Preset) failed (exit $LASTEXITCODE)." }
			[System.IO.File]::WriteAllText($PresetsFile, $OriginalPresets, $Utf8)
			# apksigner's v4 side file is only for adb incremental installs; friends get the APK alone.
			if (Test-Path "$Apk.idsig") { Remove-Item -Force "$Apk.idsig" }
			$AndroidReadme = [System.IO.File]::ReadAllText((Join-Path $Root "tools\build_readme_android.txt")).Replace("{version}", $Version).Replace("{env}", $Environment)
			[System.IO.File]::WriteAllText((Join-Path $OutDir "LIESMICH-android.txt"), $AndroidReadme.Replace("`n", "`r`n"), $Utf8)
			$Outputs += $Apk
			continue
		}

		if ($platform -eq "macos") {
			# Godot writes Soulwick.app into the zip itself; the readme is added to it.
			$Zip = Join-Path $OutDir "Soulwick-$Version-$Environment-macos.zip"
			if (Test-Path $Zip) { Remove-Item -Force $Zip }
			Write-Host "Exporting $($target.Preset) ($Environment, $Version) -> $Zip"
			& $Godot --headless --path $Root --export-release $target.Preset $Zip | Out-Host
			if ($LASTEXITCODE -ne 0 -or -not (Test-Path $Zip)) { throw "Export of $($target.Preset) failed (exit $LASTEXITCODE)." }
			Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
			$archive = [System.IO.Compression.ZipFile]::Open($Zip, [System.IO.Compression.ZipArchiveMode]::Update)
			try {
				$writer = New-Object System.IO.StreamWriter($archive.CreateEntry("LIESMICH.txt").Open(), $Utf8)
				$writer.Write($Readme)
				$writer.Dispose()
			} finally {
				$archive.Dispose()
			}
			$Outputs += $Zip
			continue
		}

		$PlatformDir = Join-Path $OutDir $platform
		if (Test-Path $PlatformDir) { Remove-Item -Recurse -Force $PlatformDir }
		New-Item -ItemType Directory -Force $PlatformDir | Out-Null
		$Binary = Join-Path $PlatformDir $target.Binary
		Write-Host "Exporting $($target.Preset) ($Environment, $Version) -> $Binary"
		# Godot is a GUI-subsystem exe: without the pipe PowerShell would not wait for the export.
		& $Godot --headless --path $Root --export-release $target.Preset $Binary | Out-Host
		if ($LASTEXITCODE -ne 0 -or -not (Test-Path $Binary)) { throw "Export of $($target.Preset) failed (exit $LASTEXITCODE)." }
		# The web folder is served as it is (GitHub Pages); it gets no readme.
		if ($platform -ne "web") {
			[System.IO.File]::WriteAllText((Join-Path $PlatformDir "LIESMICH.txt"), $Readme.Replace("`n", "`r`n"), $Utf8)
		}

		if ($platform -eq "windows" -and -not $SkipBootTest) {
			# Boot check with its own user folder, so no settings or logs land in the real one.
			$BootData = Join-Path $OutDir ".boot_userdata"
			$OldAppData = $env:APPDATA
			# Windows PowerShell 5.1 turns stderr lines of native programs into errors; Godot
			# warnings there must not stop the script (the log is checked below).
			$OldPreference = $ErrorActionPreference
			try {
				$env:APPDATA = $BootData
				$ErrorActionPreference = "Continue"
				$bootLog = & $Binary --headless --quit-after 300 -- offline 2>&1 | Out-String
				$bootExit = $LASTEXITCODE
				Write-Host $bootLog
			} finally {
				$ErrorActionPreference = $OldPreference
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
		# The exe can stay locked for a moment after the boot check (process exit, virus scanner).
		for ($attempt = 1; $attempt -le 10; $attempt++) {
			try {
				Compress-Archive -Path (Join-Path $PlatformDir "*") -DestinationPath $Zip -ErrorAction Stop
				break
			} catch {
				if ($attempt -eq 10) { throw }
				if (Test-Path $Zip) { Remove-Item -Force $Zip }
				Start-Sleep -Seconds 2
			}
		}
		$Outputs += $Zip
	}
} finally {
	[System.IO.File]::WriteAllText($EnvFile, $OriginalEnv, $Utf8)
	if ([System.IO.File]::ReadAllText($PresetsFile) -ne $OriginalPresets) {
		[System.IO.File]::WriteAllText($PresetsFile, $OriginalPresets, $Utf8)
	}
	foreach ($name in $AndroidEnvBackup.Keys) {
		[Environment]::SetEnvironmentVariable($name, $AndroidEnvBackup[$name])
	}
}

Write-Host "Done:" -ForegroundColor Green
$Outputs | ForEach-Object { Write-Host "  $_ ($([Math]::Round((Get-Item $_).Length / 1MB, 1)) MB)" }
