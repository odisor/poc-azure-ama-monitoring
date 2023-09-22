param(

    [string] $actiongroupName = "POC-ALERTS",
    [string] $dataCollectionGroups = "",
    [parameter(mandatory)][string] $tenantName,
    [Parameter(mandatory)][string] $resourceGroup

)

#--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------#
# Functions #

function Get-AlertVariables {

    if ($tenantName -eq "dev") {
      $variablesFile = "$env:BUILD_SOURCESDIRECTORY\templates\stage_dev\variables.yml"
    } elseif ($tenantName -eq "prod") {
      $variablesFile = "$env:BUILD_SOURCESDIRECTORY\templates\stage_prod\variables.yml"
    }
    $script:stage = Get-Content -Raw -Path $variablesFile | ConvertFrom-Yaml
     
    $script:workspacesResourceId = "/subscriptions/$($stage.variables.subscriptionID)/resourcegroups/$($stage.variables.resourceGroupName)/providers/microsoft.operationalinsights/workspaces/$($stage.variables.LogAnalyticsWorkspaceName)"
  
  }

#--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------#
# Main #

# Install the PowerShell-yaml module if not already installed
if (-not (Get-Module -ListAvailable -Name PowerShell-yaml)) {
    Write-Host "Installing PowerShell-yaml module"
    Install-Module -Name PowerShell-yaml -Scope CurrentUser -Force
  }


#Set VM Insights name
if ($dataCollectionGroups -eq "") {
    $dataCollectionGroups = 'MSVMI-' + $tenantName + '-' + $resourceGroup
}

# Deploy Core Resources
    try {
        Get-AlertVariables
        az deployment group create  `
        --name "common.$env:SYSTEM_DEFINITIONID.$env:BUILD_BUILDID.$env:BUILD_BUILDNUMBER" `
        --resource-group $resourceGroup `
        --template-file 'alerts/common/template.json' `
        --parameters tenant_name=$tenantName `
                     workspaces_resourceId=$workspacesResourceId `
#        --what-if 
        | Tee-Object -Variable template
    }
    catch {
        throw throw $_
    }

# Print Output Variables for Next task/job
if($?){
    try {   
        Write-Host "##vso[task.setvariable variable=dcrId;isoutput=true]$dcrId"
        Write-Host "##vso[task.setvariable variable=actionGroupId;isoutput=true]$actionGroupId"
    }
    catch {
        throw $_
    }
}