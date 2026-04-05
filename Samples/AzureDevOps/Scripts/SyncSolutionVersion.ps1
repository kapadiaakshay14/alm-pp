<#
    Script to calculate a new version number for a Dataverse solution
    and expose it back to an Azure DevOps pipeline as the variable
    "newSolutionVersion".

    It reads the current solution version from Dataverse, optionally
    compares it with the unpacked solution in source control, and then
    increments either the Build or Revision part of the version number
    depending on the flags passed in (incrementBuild / incrementRevision).
#>

param(
    # URL of the Dataverse environment (e.g. https://org.crm.dynamics.com)
    $serverURL,
    # Optional username/password for connection (used when provided)
    $username,
    $password,
    # Optional clientId/clientSecret for connection (used when provided)
    $clientId,
    $clientSecret,
    # Unique name of the Dataverse solution whose version we will update
    $solutionUniqueName,
    # When true, increment the Build number (and reset Revision)
    [bool]$incrementBuild,
    # When true, increment only the Revision number
    [bool]$incrementRevision,
    # Folder where this script expects to run so relative paths work
    $startingFilePath = ".\Build\Scripts" # Default path to the script location, modify if necessary
)

# Fail fast on any error in this script
$ErrorActionPreference = 'Stop'

try{
    # Ensure scripts from this location are allowed to run in the current user scope
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
}
catch {
    # If we cannot change the execution policy, log the error but continue
    Write-Host $_
}

# Make sure the Dataverse PowerShell module we rely on is installed and loaded
Install-Module Rnwood.Dataverse.Data.PowerShell -Scope CurrentUser -Force -AllowClobber -RequiredVersion 1.1.3 -Verbose -Repository "PSGallery"
Import-Module -Name Rnwood.Dataverse.Data.PowerShell -Verbose

# Establish a connection to Dataverse using either username/password or clientId/clientSecret
$connection = $null
if ($null -ne $username -and $null -ne $password){
    Write-Host "Connecting to Dataverse environment at" $serverURL "using Username" $username
    $connection = Get-DataverseConnection -Url $serverURL -Username $username -Password $password
}
elseif ($null -ne $clientId -and $null -ne $clientSecret){
    Write-Host "Connecting to Dataverse environment at" $serverURL "using ClientId" $clientId
    $connection = Get-DataverseConnection -Url $serverURL -ClientId $clientId -ClientSecret $clientSecret
}
else{
    # We need at least one supported credential type to connect
    throw "Invalid combination of credentials specified"
}

Write-Host "Successfully connected to Dataverse"
Write-Host "Retrieving current version of" $solutionUniqueName "solution"

# Read the current version of the solution from Dataverse
$columns = "solutionid", "uniquename", "friendlyname", "version" 
$solution = Get-DataverseRecord -Connection $connection -TableName "solution" -FilterValues @{uniquename="$solutionUniqueName"} -Columns $columns

$solutionRecord = $solution
$currentVersion = $solutionRecord.version

Write-Host "Current Version: " $currentVersion

# Ensure our working directory is the Scripts folder so relative paths below work correctly
$currentLocation = Get-Location
Write-Host "Current Directory: " $currentLocation
if (!$currentLocation.Path.EndsWith("Scripts")){
    Write-Host "Changing Directory"
    Set-Location -Path $startingFilePath
    $currentLocation = Get-Location
    Write-Host "Current Directory: " $currentLocation
}

# Split the current version into its components: Major.Minor.Build.Revision
$versionComponents = $currentVersion.Split(".")
Write-Host "Current Major: " $versionComponents[0]
Write-Host "Current Minor: " $versionComponents[1]
Write-Host "Current Build: " $versionComponents[2]
Write-Host "Current Revision: " $versionComponents[3]

# Initialise new version components; these will be overwritten once we
# decide how to increment (Build vs Revision) using the latest solution
$newMajor = "1"
$newMinor = "0"
$newbuild = "0"
$newRevision = "0"

# If we can find the unpacked solution in source control, use its
# Solution.xml to understand the latest version already committed
if (Test-Path -LiteralPath "../Solutions/$solutionUniqueName/Other/Solution.xml"){ # Modify the path as necessary depending on where in the repository the unpacked solution is located
    $solutionXml = [xml](Get-Content -LiteralPath "../Solutions/$solutionUniqueName/Other/Solution.xml") # Modify the path as necessary depending on where in the repository the unpacked solution is located
    $latestVersion = $solutionXml.ImportExportXml.SolutionManifest.Version

    Write-Host "Latest Version: " $latestVersion
    $latestVersionComponents = $latestVersion.Split(".")

    Write-Host "Latest Major: " $latestVersionComponents[0]
    Write-Host "Latest Minor:" $latestVersionComponents[1]
    Write-Host "Latest Build: " $latestVersionComponents[2]
    Write-Host "Latest Revision" $latestVersionComponents[3]

    # Always carry forward the major and minor from the environment
    $newMajor = $versionComponents[0]
    $newMinor = $versionComponents[1]

    # For build increments (typically main branch):
    # - If major/minor changed, reset build to 0
    # - Otherwise, increment the latest build number and reset revision
    if ($incrementBuild -eq $true){
        if (($latestVersionComponents[0] -ne $versionComponents[0]) -or ($latestVersionComponents[1] -ne $versionComponents[1]))
        {
            $newBuild = "0"
        }
        else{
            $newBuild = [string](([int]$latestVersionComponents[2]) + 1)
        }
        
        $newRevision = "0"
    }
    # For revision increments (typically hotfix branch):
    # - Keep the existing build
    # - Increment only the revision number
    elseif ($incrementRevision -eq $true){
        $newBuild = $latestVersionComponents[2]
        $newRevision = [string](([int]$latestVersionComponents[3]) + 1)
    }
    
}

# Recombine the individual components into a single version string
$fullVersion = $newMajor + "." + $newMinor + "." + $newBuild + "." + $newRevision

Write-Host "New Major: " $newMajor
Write-Host "New Minor: " $newMinor
Write-Host "New Build: " $newBuild
Write-Host "New Revision: " $newRevision
Write-Host "New Version: " $fullVersion

# Expose the new version back to Azure DevOps as the pipeline variable
# "newSolutionVersion" so later tasks can use it.
Write-Host "##vso[task.setvariable variable=newSolutionVersion]$fullVersion"
