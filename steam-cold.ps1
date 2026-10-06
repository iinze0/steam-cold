# steam-cold: installed Steam games not played recently, with disk size.
# Reads local app manifests only. Does not uninstall or write to Steam.
param(
    [int]$Days = 90,
    [string]$Csv,
    [switch]$All
)

$ErrorActionPreference = 'Stop'

function Get-SteamRoot {
    $keys = @(
        'HKCU:\Software\Valve\Steam',
        'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam',
        'HKLM:\SOFTWARE\Valve\Steam'
    )
    foreach ($key in $keys) {
        try {
            $path = (Get-ItemProperty -Path $key -ErrorAction Stop).SteamPath
            if ($path) {
                $path = $path -replace '/', '\'
                if (Test-Path $path) { return $path }
            }
        } catch { }
    }
    $fallback = Join-Path $env:ProgramFilesX86 'Steam'
    if (Test-Path $fallback) { return $fallback }
    throw 'Steam install not found in the registry.'
}

function Get-VdfValue([string]$text, [string]$key) {
    $pattern = '"' + [regex]::Escape($key) + '"\s+"([^"]*)"'
    $m = [regex]::Match($text, $pattern)
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Get-LibraryRoots([string]$steamRoot) {
    $roots = New-Object System.Collections.Generic.List[string]
    $roots.Add($steamRoot) | Out-Null
    $vdf = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        $text = Get-Content -Raw -Path $vdf
        foreach ($m in [regex]::Matches($text, '"path"\s+"([^"]+)"')) {
            $p = $m.Groups[1].Value -replace '\\', '\'
            if ($p -and (Test-Path $p)) { $roots.Add($p) | Out-Null }
        }
    }
    $roots | Select-Object -Unique
}

function Format-Size([long]$bytes) {
    if ($bytes -ge 1GB) { return '{0:N1} GB' -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return '{0:N0} MB' -f ($bytes / 1MB) }
    return '{0:N0} KB' -f ($bytes / 1KB)
}

$skipNames = @(
    'Steamworks Common Redistributables',
    'Proton 8.0',
    'Proton 9.0',
    'Proton Experimental',
    'Proton Hotfix',
    'Steam Linux Runtime'
)

$steam = Get-SteamRoot
$cutoff = (Get-Date).ToUniversalTime().AddDays(-$Days)
$rows = @()

foreach ($root in Get-LibraryRoots $steam) {
    $apps = Join-Path $root 'steamapps'
    if (-not (Test-Path $apps)) { continue }
    Get-ChildItem -Path $apps -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue | ForEach-Object {
        $text = Get-Content -Raw -Path $_.FullName
        $appid = Get-VdfValue $text 'appid'
        $name = Get-VdfValue $text 'name'
        $installdir = Get-VdfValue $text 'installdir'
        $sizeText = Get-VdfValue $text 'SizeOnDisk'
        $playedText = Get-VdfValue $text 'LastPlayed'
        $state = Get-VdfValue $text 'StateFlags'
        if (-not $appid -or -not $name) { return }
        if ([int]$appid -lt 10) { return }
        if ($skipNames -contains $name) { return }
        if ($name -match 'Redistributable|Dedicated Server') { return }

        $size = 0L
        if ($sizeText) { [void][long]::TryParse($sizeText, [ref]$size) }

        $played = $null
        $unix = 0L
        if ($playedText -and [long]::TryParse($playedText, [ref]$unix) -and $unix -gt 0) {
            $played = [DateTimeOffset]::FromUnixTimeSeconds($unix).UtcDateTime
        }

        $cold = (-not $played) -or ($played -lt $cutoff)
        if (-not $All -and -not $cold) { return }

        $gamePath = $null
        if ($installdir) {
            $candidate = Join-Path $apps ("common\" + $installdir)
            if (Test-Path $candidate) { $gamePath = $candidate }
        }

        $rows += [pscustomobject]@{
            AppId      = $appid
            Name       = $name
            SizeBytes  = $size
            Size       = Format-Size $size
            LastPlayed = $(if ($played) { $played.ToString('yyyy-MM-dd') } else { 'never' })
            Cold       = $cold
            Library    = $root
            Path       = $gamePath
            Uninstall  = "steam://uninstall/$appid"
            StateFlags = $state
        }
    }
}

$rows = $rows | Sort-Object SizeBytes -Descending
$total = ($rows | Measure-Object SizeBytes -Sum).Sum
if (-not $total) { $total = 0 }

if ($Csv) {
    $rows | Export-Csv -Path $Csv -NoTypeInformation -Encoding UTF8
    Write-Host "Wrote $Csv"
}

if (-not $rows) {
    Write-Host "No installed games older than $Days days."
    Write-Host "Steam: $steam"
    exit 0
}

$label = $(if ($All) { 'Installed games' } else { "Not played in $Days days" })
Write-Host "$label  ($($rows.Count) games, $(Format-Size $total))"
Write-Host "Steam: $steam"
Write-Host ''
$rows | Select-Object Name, Size, LastPlayed, AppId, Uninstall | Format-Table -AutoSize
Write-Host 'Uninstall links are not opened. Paste one into the browser or Run dialog if you want Steam to remove that game.'
