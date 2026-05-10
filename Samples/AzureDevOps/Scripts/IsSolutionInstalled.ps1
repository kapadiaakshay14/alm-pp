# Script to verify if a specified solution is installed in a particular environment, and if so, which version
param(
    $serverURL,
    $username,
    $password,
    $clientId,
    $ClientSecret,
    $solutionUniqueName,
    $solutionFilePath   

)
$upgradeSolutionName = $solutionUniqueName +'_Upgrade'
$ErrorActionPreference = 'Stop'
try{
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
}
catch {
    Write-Host $_
}

Install-Module Rnwood.Dataverse.Data.PowerShell -Scope CurrentUser -Force -AllowClobber -RequiredVersion 1.1.3 -Verbose -Repository "PSGallery"
Import-Module -Name Rnwood.Dataverse.Data.PowerShell -Verbose
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
    throw "Invalid combination of credentials specified"
}
Write-Host "Successfully connected to Dataverse"
Write-Host "Retrieving current version of" $solutionUniqueName "solution"
$columns = "solutionid", "uniquename", "friendlyname", "version" 
$solution = Get-DataverseRecord -Connection $connection -TableName "solution" -FilterValues @{uniquename="$solutionUniqueName"} -Columns $columns


if ($null -eq $solution){
    Write-Host "Solution" $solutionUniqueName "is not installed"
    Write-Host "##vso[task.setvariable variable=currentSolutionStatus;]NotInstalled"
}
else{
    Write-Host "Solution" $solutionUniqueName "version" $solution.version "is installed"
    Write-Host "##vso[task.setvariable variable=currentSolutionStatus;]"$solution.version
}

$upgradesolution = Get-DataverseRecord -Connection $connection -TableName "solution" -FilterValues @{uniquename="$upgradeSolutionName"} -Columns $columns
if ($null -eq $upgradesolution){
    Write-Host "Solution" $upgradeSolutionName "is not installed"
    Write-Host "##vso[task.setvariable variable=currentUpgradeSolutionStatus;]NotInstalled"
}
else{
    Write-Host "Solution" $upgradeSolutionName "version" $upgradesolution.version "is installed"
    Write-Host "##vso[task.setvariable variable=currentUpgradeSolutionStatus;]"$upgradesolution.version
}

Write-Host "Extracting" $solutionFilePath
Expand-Archive -Path "$solutionFilePath" -DestinationPath $solutionUniqueName -Force
Write-Host "Successfully extracted $solutionFilePath"

[XML] $solutionFileXml = Get-Content $solutionUniqueName\solution.xml
Write-Host "Attempting to install solution" $solutionUniqueName "version" $solutionFileXml.ImportExportXml.SolutionManifest.Version
Write-Host "##vso[task.setvariable variable=attemptedSolutionVersion;]"$solutionFileXml.ImportExportXml.SolutionManifest.Version