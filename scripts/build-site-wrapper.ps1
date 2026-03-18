param(
  [string]$RootDir = "."
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
  param(
    [string]$Path,
    [string]$Content
  )

  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

$rootPath = [System.IO.Path]::GetFullPath($RootDir)

$excluded = @(
  "index.html",
  "404.html"
)

$htmlFiles = Get-ChildItem -Path $rootPath -Recurse -File -Include *.html, *.htm |
  Where-Object {
    $relative = $_.FullName.Substring($rootPath.Length).TrimStart("\","/") -replace "\\","/"
    $relative -notlike "assets/*" -and
    $relative -notlike "scripts/*" -and
    $excluded -notcontains $relative
  }

$sites = @()

foreach ($file in $htmlFiles) {
  $relative = $file.FullName.Substring($rootPath.Length).TrimStart("\","/") -replace "\\","/"
  $name = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)

  $sites += [PSCustomObject]@{
    id          = ($relative.ToLowerInvariant() -replace "[^a-z0-9]+","-").Trim("-")
    name        = $name
    collection  = Split-Path $relative -Parent
    root        = Split-Path $relative -Parent
    entry       = $relative
    pageTitle   = $name
    description = "Standalone HTML export"
    pageCount   = 1
    pages       = @(
      [PSCustomObject]@{
        title      = $name
        path       = $relative
        showInTree = $true
      }
    )
  }
}

$sites = @(
  $sites | Sort-Object `
    @{ Expression = { $_.collection } }, `
    @{ Expression = { $_.name } }
)

$manifest = [PSCustomObject]@{
  generatedAt = (Get-Date).ToString("o")
  siteCount   = @($sites).Count
  sites       = @($sites)
}

$manifestPath = Join-Path $rootPath "site-index.json"
Write-Utf8NoBom -Path $manifestPath -Content (($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine)

Write-Host ("Generated wrapper manifest for {0} standalone HTML export(s)." -f @($sites).Count)