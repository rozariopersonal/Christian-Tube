$ErrorActionPreference = 'Stop'

$csvUrl = "https://raw.githubusercontent.com/openbibleinfo/Cross-References/master/topical_bible.csv"
$tempFile = "$PSScriptRoot\temp_topical.csv"
$outFile = "$PSScriptRoot\..\modules\words\data\scriptures.data.ts"

Write-Host "Downloading topical bible CSV..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $csvUrl -OutFile $tempFile

Write-Host "Processing data..."
$books = @('Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy', 'Joshua', 'Judges', 'Ruth', '1 Samuel', '2 Samuel', '1 Kings', '2 Kings', '1 Chronicles', '2 Chronicles', 'Ezra', 'Nehemiah', 'Esther', 'Job', 'Psalms', 'Proverbs', 'Ecclesiastes', 'Song of Solomon', 'Isaiah', 'Jeremiah', 'Lamentations', 'Ezekiel', 'Daniel', 'Hosea', 'Joel', 'Amos', 'Obadiah', 'Jonah', 'Micah', 'Nahum', 'Habakkuk', 'Zephaniah', 'Haggai', 'Zechariah', 'Malachi', 'Matthew', 'Mark', 'Luke', 'John', 'Acts', 'Romans', '1 Corinthians', '2 Corinthians', 'Galatians', 'Ephesians', 'Philippians', 'Colossians', '1 Thessalonians', '2 Thessalonians', '1 Timothy', '2 Timothy', 'Titus', 'Philemon', 'Hebrews', 'James', '1 Peter', '2 Peter', '1 John', '2 John', '3 John', 'Jude', 'Revelation')

$categoryMap = @{
    'love'='Love'
    'peace'='Peace'
    'anxiety'='Anxiety'
    'faith'='Faith'
    'hope'='Hope'
    'healing'='Healing'
    'forgiveness'='Forgiveness'
    'strength'='Strength'
    'joy'='Joy'
    'fear'='Fear'
}

$dict = New-Object 'System.Collections.Generic.Dictionary[String, Object]'

$reader = [System.IO.File]::OpenText($tempFile)
$isFirst = $true
while (($line = $reader.ReadLine()) -ne $null) {
    if ($isFirst) { $isFirst = $false; continue }
    
    $parts = $line.Replace('"', '').Split(',')
    if ($parts.Length -lt 3) { continue }
    
    $topic = $parts[0].ToLower().Trim()
    $reference = $parts[1].Trim()
    $votes = [int]$parts[2]
    
    if ($votes -lt 20) { continue }
    
    if ($reference -match '^(.+?)\s+(\d+):(\d+)(?:-(\d+))?$') {
        $bookName = $matches[1]
        $bookNumber = [Array]::IndexOf($books, $bookName) + 1
        if ($bookNumber -eq 0) { continue }
        
        $chapter = $matches[2]
        $startVerse = $matches[3]
        $endVerse = if ($matches[4]) { $matches[4] } else { $matches[3] }
        
        if (-not $dict.ContainsKey($reference)) {
            $obj = @{
                parsed = @{ bookName=$bookName; bookNumber=$bookNumber; chapter=$chapter; startVerse=$startVerse; endVerse=$endVerse }
                topics = New-Object 'System.Collections.Generic.HashSet[String]'
                votes = 0
            }
            $dict[$reference] = $obj
        }
        
        $entry = $dict[$reference]
        [void]$entry.topics.Add($topic)
        $entry.votes += $votes
    }
}
$reader.Close()

Write-Host "Filtering and sorting..."
$allVerses = $dict.GetEnumerator() | Where-Object { $_.Value.votes -ge 20 } | Sort-Object { $_.Value.votes } -Descending | Select-Object -First 4000

Write-Host "Generating TS file with $($allVerses.Count) verses..."
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("// AUTO-GENERATED FILE")
[void]$sb.AppendLine("// Contains $($allVerses.Count) unique references")
[void]$sb.AppendLine("export const ALL_SCRIPTURES: any[] = [")

foreach ($kvp in $allVerses) {
    $refLabel = $kvp.Key
    $verse = $kvp.Value
    
    $tags = @()
    foreach ($t in $verse.topics) {
        if ($tags.Count -ge 5) { break }
        $tags += $t
    }
    
    $category = 'General'
    foreach ($t in $tags) {
        if ($categoryMap.ContainsKey($t)) {
            $category = $categoryMap[$t]
            break
        }
    }
    
    $bg = 'mountain_dawn'
    if ($category -eq 'Peace') { $bg = 'ocean_calm' }
    if ($category -eq 'Strength') { $bg = 'desert_dusk' }
    if ($category -eq 'Love') { $bg = 'forest_sun' }
    
    $tagsStr = $tags | ForEach-Object { "'$_'" }
    $tagsJson = "[" + ($tagsStr -join ",") + "]"
    
    [void]$sb.AppendLine("  {")
    [void]$sb.AppendLine("    engine: 'scripture',")
    [void]$sb.AppendLine("    bookNumber: $($verse.parsed.bookNumber),")
    [void]$sb.AppendLine("    bookName: '$($verse.parsed.bookName)',")
    [void]$sb.AppendLine("    chapter: $($verse.parsed.chapter),")
    [void]$sb.AppendLine("    startVerse: $($verse.parsed.startVerse),")
    [void]$sb.AppendLine("    endVerse: $($verse.parsed.endVerse),")
    [void]$sb.AppendLine("    referenceLabel: '$($refLabel.Replace("'", "\'"))',")
    [void]$sb.AppendLine("    verseMappings: {},")
    [void]$sb.AppendLine("    category: '$category',")
    [void]$sb.AppendLine("    tags: $tagsJson,")
    [void]$sb.AppendLine("    backgroundPreset: '$bg',")
    $isFeatured = if ($verse.votes -gt 100) { "true" } else { "false" }
    [void]$sb.AppendLine("    isFeatured: $isFeatured,")
    [void]$sb.AppendLine("  },")
}

[void]$sb.AppendLine("];")

[System.IO.File]::WriteAllText($outFile, $sb.ToString())
Remove-Item $tempFile -Force
Write-Host "Successfully wrote $($allVerses.Count) verses to $outFile"
