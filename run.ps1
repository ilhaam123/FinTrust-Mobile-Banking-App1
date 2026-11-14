[CmdletBinding()]
param(
    [ValidateSet('windows', 'android')]
    [string]$Platform = 'windows',
    [string]$DeviceId,
    [string]$FlutterSdk,
    [switch]$Build
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
if ($FlutterSdk) {
    $flutterExecutable = Join-Path $FlutterSdk 'bin/flutter.bat'
} elseif ($flutterCommand) {
    $flutterExecutable = $flutterCommand.Source
} elseif ($env:FLUTTER_ROOT) {
    $flutterExecutable = Join-Path $env:FLUTTER_ROOT 'bin/flutter.bat'
} else {
    $flutterExecutable = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Documents/flutter/bin/flutter.bat'
}
if (-not (Test-Path $flutterExecutable)) {
    throw 'Flutter was not found. Add Flutter bin to PATH or pass -FlutterSdk C:\path\to\flutter.'
}
if ($Platform -eq 'windows' -and $env:OS -ne 'Windows_NT') {
    throw 'Windows desktop builds must run on Windows with the Visual Studio C++ workload installed.'
}

function Invoke-Flutter {
    param([string[]]$FlutterArguments)
    & $flutterExecutable @FlutterArguments
    if ($LASTEXITCODE -ne 0) { throw "Flutter failed with exit code $LASTEXITCODE." }
}

Push-Location $projectRoot
try {
    Invoke-Flutter -FlutterArguments @('pub', 'get')
    if ($Build) {
        if ($Platform -eq 'windows') {
            Invoke-Flutter -FlutterArguments @('build', 'windows', '--release', '--no-pub')
            Write-Host 'Distribute the entire build\windows\x64\runner\Release folder, including DLLs and data.'
        } else {
            Invoke-Flutter -FlutterArguments @('build', 'apk', '--debug', '--no-pub')
            Write-Host 'APK: build\app\outputs\flutter-apk\app-debug.apk'
        }
    } elseif ($Platform -eq 'windows') {
        Invoke-Flutter -FlutterArguments @('run', '-d', 'windows', '--no-pub')
    } elseif ($DeviceId) {
        Invoke-Flutter -FlutterArguments @('run', '-d', $DeviceId, '--no-pub')
    } else {
        $deviceJson = & $flutterExecutable devices --machine
        if ($LASTEXITCODE -ne 0) { throw 'Could not list Flutter devices.' }
        $devices = ($deviceJson -join "`n") | ConvertFrom-Json
        $androidDevices = @($devices | Where-Object { $_.targetPlatform -like 'android-*' })
        if ($androidDevices.Count -ne 1) {
            throw 'Connect one Android device/emulator, or pass -DeviceId with an ID from flutter devices.'
        }
        Invoke-Flutter -FlutterArguments @('run', '-d', $androidDevices[0].id, '--no-pub')
    }
} finally {
    Pop-Location
}
