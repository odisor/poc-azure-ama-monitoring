param (

    [string]$mode = "Incremental",

    [Parameter(Mandatory=$true)]
    [string]$tenantName,

    [Parameter(Mandatory=$true)]
    [string]$resourceGroup,

    [Parameter(Mandatory=$true)]
    [ValidateSet("vm_alert", "pip_alert")]
    [string]$resourceAlert,

    [Parameter(Mandatory=$true)]
    [string]$actionGroup,

    [Parameter(Mandatory=$false)]
    [string]$dataCollectionRule

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
   
  $resourceNamedict = @{
    "vm_alert" = "node"
    "pip_alert" = "pipName"
  }

  $script:alerts = $stage.variables.Keys | Where-Object { $_ -like "$resourceAlert*" }
  $script:resourceNames = $stage.variables.Keys | Where-Object { $_ -like "$($resourceNamedict.$resourceAlert)*" }
  $script:workspacesResourceId = "/subscriptions/$($stage.variables.subscriptionID)/resourcegroups/$($stage.variables.resourceGroupName)/providers/microsoft.operationalinsights/workspaces/$($stage.variables.LogAnalyticsWorkspaceName)"

}

function Set-TemplateArguments {

  Write-Host "Alert Configuration $alert : $($stage.variables.$alert)"

  $script:alertType = $stage.variables.$alert.Split(",")[0]
  $templateArgs."alert_desc" = $stage.variables.$alert.Split(",")[1]
  $templateArgs."alert_severity" = $stage.variables.$alert.Split(",")[2]
  $templateArgs."alert_threshold" = $stage.variables.$alert.Split(",")[3]
  $templateArgs."alert_evaluationFrequency" = $stage.variables.$alert.Split(",")[4]
  $templateArgs."alert_windowSize" = $stage.variables.$alert.Split(",")[5]
  $script:templateFile = "$env:BUILD_SOURCESDIRECTORY$($stage.variables.$alert.Split(",")[6])"

}

function Get-ResourceId {
      
    switch($resourceAlert) {

      "vm_alert" {$script:resourceId = "/subscriptions/$($stage.variables.subscriptionID)/resourceGroups/$($stage.variables.resourceGroupName)/providers/Microsoft.Compute/virtualMachines/$($stage.variables.$resourceName)"}
      "pip_alert" {$script:resourceId = "/subscriptions/$($stage.variables.subscriptionID)/resourceGroups/$($stage.variables.resourceGroupName)/providers/Microsoft.Network/publicIPAddresses/$($stage.variables.$resourceName)"}

    }

    Write-Host "ResourceId: $resourceId"

}

function Deploy-AlertAzCLI {

  Write-Host "Deploying alert to Azure:"
  $deploymentName = "$($stage.variables.$resourceName).$alert.$env:SYSTEM_DEFINITIONID.$env:BUILD_BUILDID.$env:BUILD_BUILDNUMBER"
  
  switch($alertType) {

    "metrics" {

      if($resourceId -like "*/providers/Microsoft.Compute/virtualMachines/*" -and $templateArgs.alert_desc -eq "cpu") {

        Write-Host "Deploying CPU Alerts to $($stage.variables.$resourceName)"
        $vm_name = $resourceId.Split("/")[-1]
        $vm_resourceGroup = $resourceId.Split("/")[4]
        $vm_location = az vm show --resource-group $vm_resourceGroup --name $vm_name --query location --output tsv

         az deployment group create `
         --mode $mode `
         --name $deploymentName `
         --resource-group $resourceGroup `
         --template-file $templateFile `
         --parameters tenant_name=$tenantName `
                      metricsAlert_severity=$($templateArgs.alert_severity) `
                      metricsAlert_threshold=$($templateArgs.alert_threshold) `
                      metricsAlert_evaluationFrequency=$($templateArgs.alert_evaluationFrequency) `
                      metricsAlert_windowSize=$($templateArgs.alert_windowSize) `
                      resourceId=$resourceId `
                      vm_location=$vm_location `
                      actionGroup_resourceId=$actionGroup `
#         --what-if
      }else{

        az deployment group create `
        --mode $mode `
        --name $deploymentName `
        --resource-group $resourceGroup `
        --template-file $templateFile `
        --parameters tenant_name=$tenantName `
                     metricsAlert_severity=$($templateArgs.alert_severity) `
                     metricsAlert_threshold=$($templateArgs.alert_threshold) `
                     metricsAlert_evaluationFrequency=$($templateArgs.alert_evaluationFrequency) `
                     metricsAlert_windowSize=$($templateArgs.alert_windowSize) `
                     resourceId=$resourceId `
                     actionGroup_resourceId=$actionGroup `
#         --what-if
     }
    }

    "logs" {

      if($resourceId -like "*/providers/Microsoft.Compute/virtualMachines/*" -and $templateArgs.alert_desc -eq "du") {

        Write-Host "Deploying Azure Monitor Linux Agent to $($stage.variables.$resourceName)"
        $vm_name = $resourceId.Split("/")[-1]
        $vm_resourceGroup = $resourceId.Split("/")[4]
        $vm_location = az vm show --resource-group $vm_resourceGroup --name $vm_name --query location --output tsv

        az deployment group create `
        --name "$($stage.variables.$resourceName).ama.$env:SYSTEM_DEFINITIONID.$env:BUILD_BUILDID.$env:BUILD_BUILDNUMBER"`
        --resource-group $vm_resourceGroup `
        --template-file "$env:BUILD_SOURCESDIRECTORY\alerts\virtual-machines\disk-usage-alert-rule\template-ama.json" `
        --parameters resourceId=$resourceId `
                     vm_location=$vm_location `
                     dataCollectionRule_resourceId=$dataCollectionRule `
#        --what-if

        Write-Host "Deploying Disk Usage Logs Alert Rule to $($stage.variables.$resourceName)"
        az deployment group create `
        --mode $mode `
        --name $deploymentName `
        --resource-group $resourceGroup `
        --template-file $templateFile `
        --parameters tenant_name=$tenantName `
                     logsAlert_severity=$($templateArgs.alert_severity) `
                     logsAlert_threshold=$($templateArgs.alert_threshold) `
                     logsAlert_evaluationFrequency=$($templateArgs.alert_evaluationFrequency) `
                     logsAlert_windowSize=$($templateArgs.alert_windowSize) `
                     resourceId=$resourceId `
                     actionGroup_resourceId=$actionGroup `
#        --what-if

      } else {

        az deployment group create `
        --mode $mode `
        --name $deploymentName `
        --resource-group $resourceGroup `
        --template-file $templateFile `
        --parameters tenant_name=$tenantName `
                     logsAlert_severity=$($templateArgs.alert_severity) `
                     logsAlert_threshold=$($templateArgs.alert_threshold) `
                     logsAlert_evaluationFrequency=$($templateArgs.alert_evaluationFrequency) `
                     logsAlert_windowSize=$($templateArgs.alert_windowSize) `
                     actionGroup_resourceId=$actionGroup `
                     workspaces_resourceId=$workspacesResourceId `
#        --what-if

      }

    }

  }

}

#--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------#
# Main #

# Install the PowerShell-yaml module if not already installed

if (-not (Get-Module -ListAvailable -Name PowerShell-yaml)) {
  Write-Host "Installing PowerShell-yaml module"
  Install-Module -Name PowerShell-yaml -Scope CurrentUser -Force
}

# Initialize variables and get values from file
$stage = @{}
$alerts = @{}
$resourceNames = @{}
$workspacesResourceId = ""
Get-AlertVariables

foreach ($resourceName in $ResourceNames) {

  # Initialize variables and get ResourceId
  $resourceId = ""
  Get-ResourceId
  
  foreach ($alert in $alerts){
    # Calculate template arguments and set hashtable 
    $templateArgs = @{}
    $alertType = ""
    $templateFile = ""
    Set-TemplateArguments

    # Deploy to Azure with AZ CLI 
    try{
      Deploy-AlertAzCLI
    }
    catch{
      throw $_
    }
  }

}