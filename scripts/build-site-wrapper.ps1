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

function Escape-RegexReplacement {
  param([string]$Value)

  return $Value.Replace('\', '\\').Replace('$', '$$')
}

function Normalize-ExportedPageHtml {
  param(
    [string]$PagePath,
    [string]$RelativePagePath,
    [string]$RootRelativePrefix
  )

  if (-not (Test-Path $PagePath)) {
    Write-Warning "Skipping missing page: $PagePath"
    return
  }

  $content = [System.IO.File]::ReadAllText($PagePath, [System.Text.Encoding]::UTF8)
  $relativePagePath = ($RelativePagePath -replace "\\", "/")
  $escapedRelativePagePath = Escape-RegexReplacement $relativePagePath

  # Keep Obsidian assets relative to the exported page folder.
  if ($content -match '<base\s+href="[^"]*"\s*/?>') {
    $content = [System.Text.RegularExpressions.Regex]::Replace(
      $content,
      '<base\s+href="[^"]*"\s*/?>',
      '<base href=".">'
    )
  }

  # Make page identity folder-aware.
  if ($content -match '<meta\s+name="pathname"\s+content="[^"]*"\s*/?>') {
    $content = [System.Text.RegularExpressions.Regex]::Replace(
      $content,
      '<meta\s+name="pathname"\s+content="[^"]*"\s*/?>',
      '<meta name="pathname" content="' + $escapedRelativePagePath + '">'
    )
  } else {
    $content = $content -replace '<head>', ('<head>' + [Environment]::NewLine + '<meta name="pathname" content="' + $relativePagePath + '">')
  }

  if ($content -match '<meta\s+property="og:url"\s+content="[^"]*"\s*/?>') {
    $content = [System.Text.RegularExpressions.Regex]::Replace(
      $content,
      '<meta\s+property="og:url"\s+content="[^"]*"\s*/?>',
      '<meta property="og:url" content="' + $escapedRelativePagePath + '">'
    )
  }

  # Rewrite only document self-links / same-page links from bare filename to repo-relative page path.
  $escapedFileName = [Regex]::Escape(([System.IO.Path]::GetFileName($relativePagePath)))

  $content = [System.Text.RegularExpressions.Regex]::Replace(
    $content,
    '(?<attr>\b(?:href|data-href|content)=")' + $escapedFileName + '(?<suffix>(?:#[^"]*)?)"',
    '${attr}' + $escapedRelativePagePath + '${suffix}"'
  )

  # Update wrapper injection.
  $injection = '<!-- vault-wrapper:start --><script defer src="' + $RootRelativePrefix + '/assets/wrapper.js" data-wrapper-root="' + $RootRelativePrefix + '"></script><!-- vault-wrapper:end -->'

  if ($content -match '(?s)<!-- vault-wrapper:start -->.*?<!-- vault-wrapper:end -->') {
    $content = $content -replace '(?s)<!-- vault-wrapper:start -->.*?<!-- vault-wrapper:end -->', $injection
  }
  elseif ($content -match '</body>') {
    $content = $content -replace '</body>', ($injection + '</body>')
  }
  else {
    $content += $injection
  }

  Write-Utf8NoBom -Path $PagePath -Content $content
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
    $fileKey = [string]$property.Key

    if ($fileKey -notmatch '\.html$') {
      continue
    }

    $relativePagePath = if ([string]::IsNullOrWhiteSpace($relativeRoot)) {
      $fileKey
    }
    else {
      ($relativeRoot.TrimEnd("/") + "/" + $fileKey)
    }

    $pages += [PSCustomObject]@{
      file       = $fileKey
      title      = if (Get-MapValue -Map $page -Key "title") { [string](Get-MapValue -Map $page -Key "title") } else { $fileKey }
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
  $entryPage = if ($entryKey) {
    $pages | Where-Object { $_.file -eq $entryKey } | Select-Object -First 1
  }
  else {
    $null
  }

  if (-not $entryPage) {
    $entryPage = $pages | Select-Object -First 1
    $entryKey = if ($entryPage) { $entryPage.file } else { $null }
  }

  $entryMetadata = if ($entryKey) { Get-MapValue -Map $webpages -Key $entryKey } else { $null }

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
    $rootRelative = Get-RootRelativePrefix -RelativeFilePath $page.path
    Normalize-ExportedPageHtml -PagePath $pagePath -RelativePagePath $page.path -RootRelativePrefix $rootRelative
  }
}

Write-Host ("Generated wrapper manifest for {0} site(s)." -f @($sites).Count)