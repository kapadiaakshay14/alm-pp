# Changes the status of different types of processes in a Dynamics 365 / Power Platform environment within a specified solution.
param(
  [Parameter(Mandatory=$true)] $serverURL,
  [Parameter(Mandatory=$false)] $username,
  [Parameter(Mandatory=$false)] $password,
  [Parameter(Mandatory=$false)] $clientId,
  [Parameter(Mandatory=$false)] $ClientSecret,
  [Parameter(Mandatory=$true)] [ValidateSet("workflow", "businessrule", "bpf", "cloudflow")] [string] $category,
  [Parameter(Mandatory=$true)] [ValidateSet("activate", "deactivate")] [string] $action,
  [Parameter(Mandatory=$true)] [string] $solutionUniqueName,
  [Parameter(Mandatory=$true)][string] $deactivationListFile
)

$ErrorActionPreference = 'Stop'

$activation = $action -eq "activate"
$categoryNumber = switch ($category)
{
    "workflow" {0}
    "businessrule" {2}
    "bpf" {4}
    "cloudflow" {5}
}

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
Write-Host "Retrieving processes with category $category for status change in '$solutionUniqueName' solution"

function getProcesses() {
  param([string] $solutionUniqueName, [int] $category)

  $fetch = @"
  <fetch>
    <entity name='workflow'>
      <attribute name='workflowid' />
      <attribute name='name' />
      <attribute name='type' />
      <attribute name='category' />
      <attribute name='solutionid' />
      <attribute name='statecode' />
      <attribute name='statuscode' />
      <filter type='and'>
        <condition attribute='category' operator='eq' value='$category' />
      </filter>
      <link-entity name='solutioncomponent' from='objectid' to='workflowid' link-type='inner'>
        <link-entity name='solution' from='solutionid' to='solutionid'>
          <attribute name='uniquename' />
          <attribute name='friendlyname' />
          <filter>
            <condition attribute='uniquename' operator='eq' value='$solutionUniqueName' />
          </filter>
        </link-entity>
      </link-entity>
    </entity>
    <order attribute='name' />
  </fetch>
"@
 Write-Host "after fectching process $fetch "
  
  $results = Get-DataverseRecord -FetchXml $fetch -Connection $connection -Debug -Verbose

  Write-Host "get crm records by fetch returned " + $results.Length + " processes"
  return $results
}

function changeWorkflowStatus() {
  param([object] $process, [bool] $activation)

  $name = $process.name
  if ($activation) {
    Write-Host "Activating process $name..."
    $process.statecode = 1
    $process.statuscode = 2
  } else {
    Write-Host "Deactivating process $name..."
    $process.statecode = 0
    $process.statuscode = 1
  }       

  try {
    Set-DataverseRecord -Connection $connection -TableName "workflow" -Id $process.Id -InputObject @{ "statecode"=$process.statecode;"statuscode"=$process.statuscode }
    Write-Host "Success"
    $result = $true
  } catch {
    Write-Host "Fail" 
    Write-Host $_.Exception 
    $result = $false
  }
  $result
}

$deactivationList = $deactivationListFile -split ","
Write-Host "deactivation list of guids $deactivationList"

$processes = [array] (getProcesses $solutionUniqueName $categoryNumber) #| ? { 
#  ($activation -and $_.statecode -eq "Draft" -and $_.workflowid -notin $deactivationList) -or ($activation -and $_.statecode -ne "Draft" -and $_.workflowid -in $deactivationList) -or (-not $activation -and $process.statecode -ne "Draft" -and $_.workflowid -in $deactivationList)})

if ($processes.Count -gt 0) {
  $activated   = 0
  $deactivated = 0
  $errors      = 0
  $total       = $processes.Count

  Write-Host "Found processes for status change with category $category in '$solutionUniqueName' solution: $total"
  foreach ($process in $processes)
  {
    if ($activation -and $process.workflowid -in $deactivationList -and $process.statecode -ne "Draft") {
      $result = changeWorkflowStatus $process $false
      if ($result) { $deactivated++ } else { $errors++ }
    } else {
      $result = changeWorkflowStatus $process $activation
      if ($result -and $activation) { 
        $activated++ 
      } elseif ($result -and -not $activation) {
        $deactivated++ 
      } else { 
        $errors++ 
      }
    }
  }
     
  Write-Host "Successfully activated $activated, deactivated $deactivated out of $total (errors $errors) processes in '$solutionUniqueName' solution"
} else {
  Write-Host "No processes with category $category found for status change in '$solutionUniqueName' solution"
}