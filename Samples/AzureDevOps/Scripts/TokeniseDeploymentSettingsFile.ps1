# Tokenises a PAC CLI generated Deployment Settings file by replacing environment variable and connection reference tokens with static values. 
# This keeps the file environment-agnostic and allows it to be used in multiple environments without modification.
param(

    [Parameter(Mandatory=$true)] $settingsFilePath,
    $environmentVariablesTokens,
    $connectionReferencesTokens

)
$ErrorActionPreference = 'Stop'

Write-Host "Settings file path:" $settingsFilePath

# Load Deployment Settings file
$deploymentSettingsContent = Get-Content -Path $settingsFilePath -Raw | ConvertFrom-Json
$environmentVariablesTokens = $environmentVariablesTokens | ConvertFrom-Json
$connectionReferencesTokens = $connectionReferencesTokens | ConvertFrom-Json

# Loop through the objects in the Deployment Settings file
foreach ($object in $deploymentSettingsContent.PSObject.Properties)
{
    Write-Host "Object Name: $($object.Name)"
    # Check if object is null or empty
    if ([string]::IsNullOrEmpty($object))
    {
        Write-Output "The $object.Name array contains a null or empty string value."

    }
    else
    {
        $objectproperties = $object.Value
        
        foreach($property in $objectproperties)
        {
            # Process Environment Variables
            if($object.Name -eq "EnvironmentVariables")
            {
                Write-Host "Schema Name: $($property.SchemaName)"
                [bool]$found = $false

                # Check if this is an expected/existing Environment Variable or a new one
                foreach($var in $environmentVariablesTokens)
                {
                    if($property.SchemaName -eq $var.SchemaName)
                    {
                        $property.Value = $var.StaticToken
                        Write-Host "Assigned Static Token: $($property.Value)"
                        $found = $true
                        break
                    }
                }
                                                           
                # It looks like this is a new/unexpected Environment Variable; fail the build to provide an opportunity for human intervention
                # and to add the new variable to the Azure DevOps EnvironmentVariablesStaticTokens repository variable
                if($found -eq $false){
                    $Exception = "Failed to find Environment Variable static token for Environment Variable with Schema Name $($property.SchemaName) in Azure DevOps EnvironmentVariablesStaticTokens repository variable"
                    throw $Exception 
                }                    
            }
            # Process Connection References
            elseif($object.Name -eq "ConnectionReferences")
            {

                Write-Host "Connector ID: $($property.ConnectorId)"
                Write-Host "Logical Name: $($property.LogicalName)"
                [bool]$found = $false
                
                # Check if this is an expected/existing Connection Reference or a new one
                foreach($conn in $connectionReferencesTokens)
                {                                                                            
                    if($property.ConnectorId -eq $conn.ConnectorId){
                        
                        $property.ConnectionId = $conn.StaticToken
                        Write-Host " Assigned Static Token: $($property.ConnectionId)"
                        $found = $true
                        break
                    }
                }
                # It looks like this is a new/unexpected Connection Reference; fail the build to provide an opportunity for human intervention
                # and to add the new variable to the Azure DevOps ConnectionReferencesStaticTokens repository variable
                if($found -eq $false){
                    $Exception = "Failed to find Connection Reference static token for Connector with connector id $($property.ConnectorId) in Azure DevOps ConnectionReferencesStaticTokens repository variable"
                    throw $Exception 
                }                
            }
        }
    }
}

# Update Deployment Settings file
Set-Content ($deploymentSettingsContent | ConvertTo-Json -Depth 4) -Path $settingsFilePath