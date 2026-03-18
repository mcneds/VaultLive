param(
  [string]$RootDir = "."
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Web.Extensions

function Read-JsonMap {
  param(
    [string]$Path
  )

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
  param(
    [string]$RelativeFilePath
  )

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
  param(
    [string]$Text
  )

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

function Convert-ToPlainObject {
  param(
    $Value
  )

  if ($null -eq $Value) {
    return $null
  }

  if ($Value -is [System.Collections.IDictionary]) {
    $result = @{}
    foreach ($key in $Value.Keys) {
      $result[$key] = Convert-ToPlainObject -Value $Value[$key]
    }
    return $result
  }

  if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
    $list = @()
    foreach ($item in $Value) {
      $list += ,(Convert-ToPlainObject -Value $item)
    }
    return $list
  }

  return $Value
}

function Rewrite-RelativeDocLink {
  param(
    [string]$Link,
    [string]$RelativeRoot
  )

  if ([string]::IsNullOrWhiteSpace($Link)) {
    return $Link
  }

  if ($Link -match '^(?:[a-z]+:)?//' -or $Link.StartsWith("#") -or $Link.StartsWith("?")) {
    return $Link
  }

  $parts = $Link -split '#', 2
  $pathPart = $parts[0]
  $hashPart = if ($parts.Count -gt 1) { "#" + $parts[1] } else { "" }

  if ([string]::IsNullOrWhiteSpace($pathPart)) {
    return $Link
  }

  if ($pathPart.StartsWith("/")) {
    return $Link
  }

  $joined = if ([string]::IsNullOrWhiteSpace($RelativeRoot)) {
    $pathPart
  } else {
    ($RelativeRoot.TrimEnd("/") + "/" + $pathPart.TrimStart("/"))
  }

  return ($joined -replace "\\", "/") + $hashPart
}

function Update-MetadataFile {
  param(
    [string]$MetadataPath,
    [string]$RelativeRoot
  )

  $metadata = Convert-ToPlainObject -Value (Read-JsonMap -Path $MetadataPath)

  $relativeRoot = ($RelativeRoot -replace "\\", "/").Trim("/")
  $pathToRoot = if ([string]::IsNullOrWhiteSpace($relativeRoot)) { "." } else { (($relativeRoot -split "/") | ForEach-Object { ".." }) -join "/" }

  $oldWebpages = Get-MapValue -Map $metadata -Key "webpages" -Default @{}
  $newWebpages = [ordered]@{}

  foreach ($key in $oldWebpages.Keys) {
    $page = Convert-ToPlainObject -Value $oldWebpages[$key]
    $newKey = if ([string]::IsNullOrWhiteSpace($relativeRoot)) { $key } else { ($relativeRoot + "/" + $key) }

    if ($page.ContainsKey("links")) {
      $page["links"] = @(
        $page["links"] | ForEach-Object {
          Rewrite-RelativeDocLink -Link ([string]$_) -RelativeRoot $relativeRoot
        }
      )
    }

    if ($page.ContainsKey("backlinks")) {
      $page["backlinks"] = @(
        $page["backlinks"] | ForEach-Object {
          Rewrite-RelativeDocLink -Link ([string]$_) -RelativeRoot $relativeRoot
        }
      )
    }

    if ($page.ContainsKey("fullURL")) {
      $page["fullURL"] = $newKey
    }

    if ($page.ContainsKey("exportPath")) {
      $page["exportPath"] = $newKey
    }

    if ($page.ContainsKey("pathToRoot")) {
      $page["pathToRoot"] = $pathToRoot
    }

    $newWebpages[$newKey] = $page
  }

  $metadata["webpages"] = $newWebpages

  $oldFileInfo = Get-MapValue -Map $metadata -Key "fileInfo" -Default @{}
  $newFileInfo = [ordered]@{}

  foreach ($key in $oldFileInfo.Keys) {
    $info = Convert-ToPlainObject -Value $oldFileInfo[$key]

    $newKey = if ($key -match '\.html($|#|\?)' -and -not [string]::IsNullOrWhiteSpace($relativeRoot)) {
      ($relativeRoot + "/" + $key)
    } else {
      $key
    }

    if ($info.ContainsKey("exportPath") -and $info["exportPath"] -match '\.html$' -and -not [string]::IsNullOrWhiteSpace($relativeRoot)) {
      $info["exportPath"] = ($relativeRoot + "/" + $info["exportPath"])
    }

    if ($info.ContainsKey("backlinks")) {
      $info["backlinks"] = @(
        $info["backlinks"] | ForEach-Object {
          Rewrite-RelativeDocLink -Link ([string]$_) -RelativeRoot $relativeRoot
        }
      )
    }

    $newFileInfo[$newKey] = $info
  }

  $metadata["fileInfo"] = $newFileInfo

  if ($metadata.ContainsKey("shownInTree")) {
    $metadata["shownInTree"] = @(
      $metadata["shownInTree"] | ForEach-Object {
        Rewrite-RelativeDocLink -Link ([string]$_) -RelativeRoot $relativeRoot
      }
    )
  }

  if ($metadata.ContainsKey("allFiles")) {
    $metadata["allFiles"] = @(
      $metadata["allFiles"] | ForEach-Object {
        $item = [string]$_
        if ($item -match '\.html$' -and -not [string]::IsNullOrWhiteSpace($relativeRoot)) {
          ($relativeRoot + "/" + $item)
        } else {
          $item
        }
      }
    )
  }

  if ($metadata.ContainsKey("sourceToTarget")) {
    $oldSourceToTarget = Get-MapValue -Map $metadata -Key "sourceToTarget" -Default @{}
    $newSourceToTarget = [ordered]@{}

    foreach ($sourceKey in $oldSourceToTarget.Keys) {
      $targetValue = [string]$oldSourceToTarget[$sourceKey]
      if ($targetValue -match '\.html$' -and -not [string]::IsNullOrWhiteSpace($relativeRoot)) {
        $newSourceToTarget[$sourceKey] = ($relativeRoot + "/" + $targetValue)
      } else {
        $newSourceToTarget[$sourceKey] = $targetValue
      }
    }

    $metadata["sourceToTarget"] = $newSourceToTarget
  }

  $json = $metadata | ConvertTo-Json -Depth 100
  Write-Utf8NoBom -Path $MetadataPath -Content ($json + [Environment]::NewLine)
}

function Update-PageHtml {
  param(
    [string]$PagePath,
    [string]$RelativePagePath,
    [string]$RootRelativePrefix
  )

  $content = [System.IO.File]::ReadAllText($PagePath, [System.Text.Encoding]::UTF8)
  $relativePagePath = ($RelativePagePath -replace "\\", "/")

  $content = [System.Text.RegularExpressions.Regex]::Replace(
    $content,
    '<meta\s+name="pathname"\s+content="[^"]*"\s*/?>',
    ('<meta name="pathname" content="' + $relativePagePath + '">')
  )

  $content = [System.Text.RegularExpressions.Regex]::Replace(
    $content,
    '<meta\s+property="og:url"\s+content="[^"]*"\s*/?>',
    ('<meta property="og:url" content="' + $relativePagePath + '">')
  )

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
    $relativePagePath = if ([string]::IsNullOrWhiteSpace($relativeRoot)) {
      $property.Key
    }
    else {
      ($relativeRoot.TrimEnd("/") + "/" + $property.Key)
    }

    $pages += [PSCustomObject]@{
      file = [string]$property.Key
      title = if (Get-MapValue -Map $page -Key "title") { [string](Get-MapValue -Map $page -Key "title") } else { [string]$property.Key }
      path = $relativePagePath
      showInTree = [bool](Get-MapValue -Map $page -Key "showInTree" -Default $false)
      treeOrder = if ($null -ne (Get-MapValue -Map $page -Key "treeOrder")) { [int](Get-MapValue -Map $page -Key "treeOrder") } else { 999999 }
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
        title = $_.title
        path = $_.path
        showInTree = $_.showInTree
      }
    }
  )

  $sites += [PSCustomObject]@{
    id = if ([string]::IsNullOrWhiteSpace($relativeRoot)) { "root-site" } else { ($relativeRoot.ToLowerInvariant() -replace "[^a-z0-9]+", "-").Trim("-") }
    name = Split-Path $siteDir -Leaf
    collection = $collection
    root = $relativeRoot
    entry = if ($entryPage) { $entryPage.path } else { "" }
    pageTitle = if ($entryMetadata -and (Get-MapValue -Map $entryMetadata -Key "title")) { [string](Get-MapValue -Map $entryMetadata -Key "title") } elseif ($entryPage) { $entryPage.title } else { "" }
    description = if ($entryMetadata) { Get-CleanSnippet -Text ([string](Get-MapValue -Map $entryMetadata -Key "description" -Default "")) } else { "" }
    pageCount = @($pageSummary).Count
    pages = $pageSummary
  }

  Update-MetadataFile -MetadataPath $metadataFile.FullName -RelativeRoot $relativeRoot
}

$sites = @(
  $sites | Sort-Object `
    @{ Expression = { $_.collection } }, `
    @{ Expression = { $_.name } }, `
    @{ Expression = { $_.pageTitle } }
)

$manifest = [PSCustomObject]@{
  generatedAt = (Get-Date).ToString("o")
  siteCount = @($sites).Count
  sites = @($sites)
}

$manifestPath = Join-Path $rootPath "site-index.json"
Write-Utf8NoBom -Path $manifestPath -Content (($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine)

foreach ($site in $sites) {
  foreach ($page in $site.pages) {
    $pagePath = Join-Path $rootPath ($page.path -replace "/", "\")
    $rootRelative = Get-RootRelativePrefix -RelativeFilePath $page.path
    Update-PageHtml -PagePath $pagePath -RelativePagePath $page.path -RootRelativePrefix $rootRelative
  }
}

Write-Host ("Generated wrapper manifest for {0} site(s)." -f @($sites).Count)