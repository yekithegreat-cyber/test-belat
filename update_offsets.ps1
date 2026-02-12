param(
  [string]$DumpPath = "dump.h",
  [string]$DumpJsonPath = "dump.json",
  [string]$DumpedPath = "dumped.html",
  [string]$FflagsPath = "fflags.html",
  [string]$JsonOffsetsPath = "jsonoffsets.html"
)

# Check for input files
$hasDumpH = Test-Path -LiteralPath $DumpPath
$hasDumpJson = Test-Path -LiteralPath $DumpJsonPath

if (-not $hasDumpH -and -not $hasDumpJson) {
  throw "Missing input files: Neither $DumpPath nor $DumpJsonPath found"
}

if (-not (Test-Path -LiteralPath $DumpedPath)) {
  throw "Missing dumped.html file: $DumpedPath"
}
if (-not (Test-Path -LiteralPath $FflagsPath)) {
  Write-Warning "Warning: fflags.html not found at $FflagsPath - only updating dumped.html"
  $UpdateFflags = $false
} else {
  $UpdateFflags = $true
}

function ConvertTo-HtmlEscaped([string]$s) {
  if ($null -eq $s) { return "" }
  return ($s -replace "&", "&amp;" -replace "<", "&lt;" -replace ">", "&gt;")
}

# Initialize variables
$offsets = @()
$version = "unknown"
$offsetCount = 0
$sourceFiles = @()

# Read from dump.h if it exists
if ($hasDumpH) {
    $sourceFiles += $DumpPath
    Write-Host "Loading offsets from $DumpPath..."
    # Read dump.h as lines (keep order)
    $lines = Get-Content -LiteralPath $DumpPath

    # First pass: extract version and count
    foreach ($line in $lines) {
        if ($line -match '//\s*roblox version\s*-\s*([^\s<]+)') {
            if ($version -eq "unknown") {
                $version = $matches[1].Trim()
            }
        }
        elseif ($line -match '//\s*total offsets\s*-\s*(\d+)') {
            if ($offsetCount -eq 0) {
                $offsetCount = [int]$matches[1]
            }
        }
        elseif ($line -match '\s*inline\s+uintptr_t\s+([A-Za-z0-9_]+)\s*=\s*(0x[0-9a-fA-F]+)') {
            $offsets += [PSCustomObject]@{
                Name = $matches[1]
                Value = $matches[2]
            }
        }
    }
}

# Read from dump.json if it exists (load AFTER dump.h so dump.json wins on duplicates)
if ($hasDumpJson) {
    $sourceFiles += $DumpJsonPath
    Write-Host "Loading offsets from $DumpJsonPath..."
    $dumpJson = Get-Content -LiteralPath $DumpJsonPath -Raw | ConvertFrom-Json

    if ($dumpJson.PSObject.Properties.Name -contains 'roblox_version') {
        $version = $dumpJson.roblox_version
    }
    if ($dumpJson.PSObject.Properties.Name -contains 'total_offsets') {
        $offsetCount = [int]$dumpJson.total_offsets
    }

    if ($null -ne $dumpJson.fflags) {
        foreach ($p in $dumpJson.fflags.PSObject.Properties) {
            $decimalValue = [UInt64]$p.Value
            $hexValue = ('0x{0:X}' -f $decimalValue)
            $offsets += [PSCustomObject]@{
                Name = $p.Name
                Value = $hexValue
            }
        }

        if ($offsetCount -eq 0) {
            $offsetCount = $dumpJson.fflags.PSObject.Properties.Count
        }
    }
}

# Remove duplicates (keep last occurrence)
$uniqueOffsets = @{}
foreach ($offset in $offsets) {
    $uniqueOffsets[$offset.Name] = $offset.Value
}
$offsets = $uniqueOffsets.GetEnumerator() | ForEach-Object {
    [PSCustomObject]@{
        Name = $_.Key
        Value = $_.Value
    }
}

# Sort offsets by name
$offsets = $offsets | Sort-Object Name

# Update offset count if not set
if ($offsetCount -eq 0) {
    $offsetCount = $offsets.Count
}

# Generate HTML content
$sourceList = $sourceFiles -join ", "
$now = Get-Date -Format "HH:mm dd/MM/yy"

# Update dumped.html
$dumpedHtml = Get-Content -LiteralPath $DumpedPath -Raw
$dumpedOffsetItems = ($offsets | ForEach-Object {
    $name = $_.Name
    $value = $_.Value
    "    <div class='offset-item'><span class='offset-name'>$name</span><span class='offset-value'>$value</span></div>"
}) -join "`n"
$dumpedHtml = $dumpedHtml -replace '(?s)(<div class="offset-list">).*?(</div>)', "`$1`n$dumpedOffsetItems`n  `$2"

# Update version and timestamp
$dumpedHtml = $dumpedHtml -replace '(?s)(<div class="header-info">\s*<p>Version: ).*?(</p>)', "`$1$version`$2"
$dumpedHtml = $dumpedHtml -replace '(?s)(<div class="header-info">\s*<p>Dumped at: ).*?(</p>)', "`$1$now`$2"

Set-Content -LiteralPath $DumpedPath -Value $dumpedHtml -Encoding UTF8
Write-Host "Updated C++ offsets in $DumpedPath from: $sourceList"

# Update jsonoffsets.html
$jsonContent = @{
    roblox_version = $version
    dumped_at = $now
    total_offsets = $offsetCount
    fflags = @{}
}

foreach ($offset in $offsets) {
    $decimalValue = [Convert]::ToUInt64($offset.Value, 16)
    $jsonContent.fflags[$offset.Name] = $decimalValue
}

$jsonContent = $jsonContent | ConvertTo-Json -Depth 10
Set-Content -LiteralPath $JsonOffsetsPath -Value $jsonContent -Encoding UTF8
Write-Host "Updated JSON offsets in $JsonOffsetsPath from: $sourceList"

# Update fflags.html if it exists
if ($UpdateFflags) {
    $fflagsHtml = Get-Content -LiteralPath $FflagsPath -Raw
    
    # Update the offsets list in fflags.html (only the content inside the first container)
    $fflagsPattern = '(?s)(<div class="space-y-4 max-h-96 overflow-y-auto custom-scrollbar">\s*)(.*?)(\s*<\/div>\s*<\/div>\s*<!-- OFFSETS\.JSON Box)'
    
    $fflagsContent = (($offsets | ForEach-Object {
        $name = $_.Name
        $value = $_.Value
        "<div class='offset-item p-4 rounded-lg'><div class='flex justify-between items-center'><span class='text-sm'>$name</span><span class='offset-value'>$value</span></div></div>"
    }) -join "`n")
    
    $fflagsUpdated = [regex]::Replace(
        $fflagsHtml,
        $fflagsPattern,
        { param($m) $m.Groups[1].Value + $fflagsContent + $m.Groups[3].Value }
    )
    
    # Update the version in the header
    $fflagsHeaderPattern = '(?s)(<h2 class="font-serif text-3xl font-bold text-center text-brandRed">FFLAGS OFFSETS<\/h2>\s*<p class="text-center text-white\/70 mt-2">Roblox Fast Flags Memory Offsets Database<\/p>\s*<p class="text-center text-sm text-gray-400 mt-2">Version: )([^<]+)(<\/p>)'
    
    $fflagsUpdated = [regex]::Replace(
        $fflagsUpdated,
        $fflagsHeaderPattern,
        "`$1$version`$3"
    )
    
    # Update the total count in the header if it exists
    $fflagsCountPattern = '(?s)(<p class="text-center text-sm text-gray-400">Total Offsets: )([^<]+)(<\/p>)'
    $fflagsUpdated = [regex]::Replace(
        $fflagsUpdated,
        $fflagsCountPattern,
        "`$1$($offsetCount -replace '\B(?=(\d{3})+(?!\d))', ',')`$3"
    )
    
    Set-Content -LiteralPath $FflagsPath -Value $fflagsUpdated -Encoding UTF8
    Write-Host "Updated offsets in $FflagsPath"
}

Write-Host "Update complete! Processed $($offsets.Count) unique offsets."
