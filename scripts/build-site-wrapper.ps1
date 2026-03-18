param(
  [string]$RootDir = "."
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Web.Extensions

function Read-JsonMap {
  param([string]$Path)

  $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
  $serializer.MaxJsonLength = [int]::MaxValue
  return $serializer.DeserializeObject((Get-Content -Raw -Encoding UTF8 -Path $Path))
}

function Get-MapValue {
  param(
    $Map,
    [string]$Key,
    $Default = $null
  )

  if ($Map -is [System.Collections.IDictionary] -and ($Map.Keys -contains $Key)) {
    return $Map[$Key]
  }

  return $Default
}

function Get-PosixRelativePath {
  param(
    [string]$BasePath,
    [string]$TargetPath
  )

  $resolvedBase = [System.IO.Path]::GetFullPath($BasePath)
  $resolvedTarget = [System.IO.Path]::GetFullPath($TargetPath)

  if ($resolvedTarget.StartsWith($resolvedBase, [System.StringComparison]::OrdinalIgnoreCase)) {
    $relative = $resolvedTarget.Substring($resolvedBase.Length).TrimStart("\", "/")
    return ($relative -replace "\\", "/")
  }

  throw "Target path '$TargetPath' is outside the wrapper root '$BasePath'."
}

function Get-RootRelativePrefix {
  param([string]$RelativeFilePath)

  $directory = Split-Path $RelativeFilePath -Parent

  if ([string]::IsNullOrWhiteSpace($directory)) {
    return "."
  }

  $segments = $directory -split "[\\/]" | Where-Object { $_ }

  if (-not $segments.Count) {
    return "."
  }

  return (($segments | ForEach-Object { ".." }) -join "/")
}

function Get-CleanSnippet {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return ""
  }

  $clean = [System.Text.RegularExpressions.Regex]::Replace($Text, "<[^>]+>", " ")
  $clean = [System.Text.RegularExpressions.Regex]::Replace($clean, "\s+", " ").Trim()

  if ($clean.Length -le 180) {
    return $clean
  }

  return ($clean.Substring(0, 177).TrimEnd() + "...")
}

function Write-Utf8NoBom {
  param(
    [string]$Path,
    [string]$Content
  )

  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Normalize-RepoRelativePagePath {
  param(
    [string]$RelativeRoot,
    [string]$PageKey
  )

  $root = ($RelativeRoot -replace "\\", "/").Trim("/")
  $key = ([string]$PageKey -replace "\\", "/").TrimStart("/")

  if ([string]::IsNullOrWhiteSpace($root)) {
    return $key
  }

  if ($key -eq $root -or $key.StartsWith($root + "/")) {
    return $key
  }

  return ($root + "/" + $key)
}

$rootPath = [System.IO.Path]::GetFullPath($RootDir)
$metadataFiles = Get-ChildItem -Path $rootPath -Recurse -Filter metadata.json | Where-Object { $_.FullName -match "[\\/]site-lib[\\/]metadata\.json$" }
$sites = @()

foreach ($metadataFile in $metadataFiles) {
  $metadata = Read-JsonMap -Path $metadataFile.FullName
  $siteLibDir = Split-Path $metadataFile.FullName -Parent
  $siteDir = Split-Path $siteLibDir -Parent
  $relativeRoot = Get-PosixRelativePath -BasePath $rootPath -TargetPath $siteDir
  $collection = Split-Path $relativeRoot -Parent
  $webpages = Get-MapValue -Map $metadata -Key "webpages" -Default @{}
  $shownInTree = @(Get-MapValue -Map $metadata -Key "shownInTree" -Default @())

  if ([string]::IsNullOrWhiteSpace($collection) -or $collection -eq ".") {
    $collection = "Root"
  }

  $pages = @()

  foreach ($property in $webpages.GetEnumerator()) {
    $page = $property.Value
    $relativePagePath = Normalize-RepoRelativePagePath -RelativeRoot $relativeRoot -PageKey ([string]$property.Key)

    $normalizedFileKey = [string]$property.Key
    if (-not [string]::IsNullOrWhiteSpace($relativeRoot)) {
      $prefix = ($relativeRoot.TrimEnd("/") + "/")
      if ($normalizedFileKey.StartsWith($prefix)) {
        $normalizedFileKey = $normalizedFileKey.Substring($prefix.Length)
      }
    }

    $pages += [PSCustomObject]@{
      file       = $normalizedFileKey
      title      = if (Get-MapValue -Map $page -Key "title") { [string](Get-MapValue -Map $page -Key "title") } else { [string]$property.Key }
      path       = $relativePagePath
      showInTree = [bool](Get-MapValue -Map $page -Key "showInTree" -Default $false)
      treeOrder  = if ($null -ne (Get-MapValue -Map $page -Key "treeOrder")) { [int](Get-MapValue -Map $page -Key "treeOrder") } else { 999999 }
    }
  }

  $pages = @(
    $pages | Sort-Object `
      @{ Expression = { if ($_.showInTree) { 0 } else { 1 } } }, `
      @{ Expression = { $_.treeOrder } }, `
      @{ Expression = { $_.title } }
  )

  $entryKey = if ($shownInTree.Count -gt 0) { [string]$shownInTree[0] } else { $null }

  if (-not [string]::IsNullOrWhiteSpace($relativeRoot) -and -not [string]::IsNullOrWhiteSpace($entryKey)) {
    $prefix = ($relativeRoot.TrimEnd("/") + "/")
    if ($entryKey.StartsWith($prefix)) {
      $entryKey = $entryKey.Substring($prefix.Length)
    }
  }

  $entryPage = if ($entryKey) {
    $pages | Where-Object { $_.file -eq $entryKey } | Select-Object -First 1
  } else {
    $null
  }

  if (-not $entryPage) {
    $entryPage = $pages | Select-Object -First 1
    $entryKey = if ($entryPage) { $entryPage.file } else { $null }
  }

  $entryMetadata = if ($entryKey) {
    $candidateKeys = @($entryKey, (Normalize-RepoRelativePagePath -RelativeRoot $relativeRoot -PageKey $entryKey))
    $found = $null
    foreach ($candidate in $candidateKeys) {
      $candidateValue = Get-MapValue -Map $webpages -Key $candidate
      if ($null -ne $candidateValue) {
        $found = $candidateValue
        break
      }
    }
    $found
  } else {
    $null
  }

  $pageSummary = @(
    $pages | ForEach-Object {
      [PSCustomObject]@{
        title      = $_.title
        path       = $_.path
        showInTree = $_.showInTree
      }
    }
  )

  $sites += [PSCustomObject]@{
    id          = if ([string]::IsNullOrWhiteSpace($relativeRoot)) { "root-site" } else { ($relativeRoot.ToLowerInvariant() -replace "[^a-z0-9]+", "-").Trim("-") }
    name        = Split-Path $siteDir -Leaf
    collection  = $collection
    root        = $relativeRoot
    entry       = if ($entryPage) { $entryPage.path } else { "" }
    pageTitle   = if ($entryMetadata -and (Get-MapValue -Map $entryMetadata -Key "title")) { [string](Get-MapValue -Map $entryMetadata -Key "title") } elseif ($entryPage) { $entryPage.title } else { "" }
    description = if ($entryMetadata) { Get-CleanSnippet -Text ([string](Get-MapValue -Map $entryMetadata -Key "description" -Default "")) } else { "" }
    pageCount   = @($pageSummary).Count
    pages       = $pageSummary
  }
}

$sites = @(
  $sites | Sort-Object `
    @{ Expression = { $_.collection } }, `
    @{ Expression = { $_.name } }, `
    @{ Expression = { $_.pageTitle } }
)

$manifest = [PSCustomObject]@{
  generatedAt = (Get-Date).ToString("o")
  siteCount   = @($sites).Count
  sites       = @($sites)
}

$manifestPath = Join-Path $rootPath "site-index.json"
Write-Utf8NoBom -Path $manifestPath -Content (($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine)

foreach ($site in $sites) {
  foreach ($page in $site.pages) {
    $pagePath = Join-Path $rootPath ($page.path -replace "/", "\")
    if (-not (Test-Path $pagePath)) {
      Write-Warning "Skipping missing page: $pagePath"
      continue
    }

    $rootRelative = Get-RootRelativePrefix -RelativeFilePath $page.path
    $injection = "<!-- vault-wrapper:start --><script defer src=""$rootRelative/assets/wrapper.js"" data-wrapper-root=""$rootRelative""></script><!-- vault-wrapper:end -->"
    $content = [System.IO.File]::ReadAllText($pagePath, [System.Text.Encoding]::UTF8)

    if ($content -match "(?s)<!-- vault-wrapper:start -->.*?<!-- vault-wrapper:end -->") {
      $content = $content -replace "(?s)<!-- vault-wrapper:start -->.*?<!-- vault-wrapper:end -->", $injection
    }
    elseif ($content -match "</body>") {
      $content = $content -replace "</body>", ($injection + "</body>")
    }
    else {
      $content += $injection
    }

    Write-Utf8NoBom -Path $pagePath -Content $content
  }
}

Write-Host ("Generated wrapper manifest for {0} site(s)." -f @($sites).Count)