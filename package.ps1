param(
    [Parameter(Mandatory = $True, Position = 1)]
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [string]$modDir,

    [Parameter(Mandatory = $True, Position = 2)]
    [ValidateSet("major", "minor", "patch")]
    [string]$versionPart
)

if (-not (Test-Path -Path $modDir -PathType Container)) {
    Write-Host "Directory not found: $modDir"
    exit
}

$iniFilePath = Join-Path -Path $modDir -ChildPath "modinfo.ini"
$iniContent = Get-Content -Path $iniFilePath

foreach ($line in $iniContent) {
    if ($line -match '^version\s*=\s*(\d+)\.(\d+)\.(\d+)$') {
        $major = [int]$matches[1]
        $minor = [int]$matches[2]
        $patch = [int]$matches[3]
        
        switch ($versionPart) {
            "major" {
                $major++
                $minor = 0
                $patch = 0
            }
            "minor" {
                $minor++
                $patch = 0
            }
            "patch" {
                $patch++
            }
        }
        
        $newVersionLine = "version=$major.$minor.$patch"
        $iniContent = $iniContent -replace "^version\s*=.*$", $newVersionLine
        $iniContent | Set-Content -Path $iniFilePath
        Write-Host "Version bumped to $major.$minor.$patch"
        break
    }
}

$directoryName = (Get-Item $modDir).Name
$zipFilePath = Join-Path -Path "." -ChildPath "$directoryName.zip"
$zipContents = Join-Path -Path $modDir -ChildPath "*"
Remove-Item -Path $zipFilePath
Compress-Archive -Path $zipContents -DestinationPath $zipFilePath
Write-Host "Packaged mod to: $zipFilePath"
