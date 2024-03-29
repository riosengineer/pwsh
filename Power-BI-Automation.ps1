<# .NOTES
NAME        :  Power-BI-Automation
LAST UPDATED:  14/02/2022
VERSION: 1.0
AUTHOR      :  Dan Rios
# If using in an Azure Runbook the following modules need to be imported to the automation account: 
#
## PowerBI Mgmt PS Modules and their dependencies
# MicrosoftPowerBIMgmt
# MicrosoftPowerBIMgmt.Admin
# MicrosoftPowerBIMgmt.Data
# MicrosoftPowerBIMgmt.Reports
# MicrosoftPowerBIMmgt.Workspaces
# MicrosoftPowerBIMmgt.Capacities
#
#
# Configure Managed Identity on the Automation Account for AzAccount Module Auth
# https://powerbi.microsoft.com/en-us/blog/use-power-bi-api-with-service-principal-preview/
# Only require Application - Tenant Read/Write/All on API App Permissions no delegate permissions needed
#>
  
param (
  [parameter(Mandatory=$true)]
  [string]$tenantid,
  [parameter(Mandatory=$true)]
  [string]$appid,
  [parameter(Mandatory=$true)]
  [string]$resourcegroupname,
  [parameter(Mandatory=$true)]
  [string]$Workspacename
)

# $AppId = "AppId
# $TenantId = "TenantID"

# Connect to AzAccount PS Module & populate SQL Server
Connect-AzAccount -Identity
$sqlserver = Get-AzSqlServer -ResourceGroupName $resourcegroupname | Select -ExpandProperty FullyQualifiedDomainName
# Get Azure App Secret
$keyVault = Get-AzKeyVaultSecret -VaultName "VaultName" -Name "AppName" -AsPlainText
$keyVault | ConvertTo-SecureString -AsPlainText -Force

# Create secure string & credential for application id and client secret
$SecurePassword = ConvertTo-SecureString $KeyVault -Force -AsPlainText
$Credential = New-Object Management.Automation.PSCredential($AppId, $SecurePassword)

# Connect to the Power BI service with Service Principal
Connect-PowerBIServiceAccount -ServicePrincipal -TenantId $TenantId -Credential $Credential

# Create new workspace
New-PowerBIWorkspace -Name $workspacename -Verbose
$workspace = Get-PowerBIworkspace -Name $workspacename
$workspaceid = $workspace.id

# Download PBIX files
Invoke-WebRequest "Direct URL to ZIP folder" -Outfile "Reports.zip"
Expand-Archive -Path Reports.zip -DestinationPath .\

# Upload PBIX files to workspace
New-PowerBIReport -Path .\Report.pbix -WorkspaceId $workspaceid -Verbose

# Add AD Group or Users to workspace as Administrator
Add-PowerBIWorkspaceUser -Id $workspaceid -UserEmailAddress dan.rios@UPN.com -AccessRight Admin
Add-PowerBIWorkspaceUser -Id $workspaceid -PrincipalType Group -Identifier "AAD ObjectID" -AccessRight Admin

# Get Dataset GUID Id
$dataset = Get-PowerBIDataset -WorkspaceId $workspaceid 
$datasetid = $dataset.id

# Take over data sets
foreach ($datasetids in $datasetid){
    Invoke-PowerBIRestMethod -Url "https://api.powerbi.com/v1.0/myorg/groups/$workspaceid/datasets/$datasetids/Default.Takeover" -Method Post -Verbose
}

# Set Content to JSON 
$content = 'application/json'

# Compile API Body request JSON for SQL Server Details
$Parameters = @{
  "updateDetails"= @(
      @{
          "name"="SQL Database";
          "newValue"="Db001prod";
       },
      @{
          "name"="SQL Server";
          "newValue"="$($sqlserver)";
       }            
  )
}

$Params = $Parameters | ConvertTo-Json -Compress

foreach ($datasets in $dataset){
  # Invoke PowerBI API 
  Invoke-PowerBIRestMethod -Url $urlParams -Method Post -Body $Params -ContentType $content -Verbose
}

# refresh now
[string]$datasetid
foreach ($datasetids in $datasetid) {
# Refresh Datasets now 
Write-Output Refreshing dataset: $datasetids in $workspacename
Invoke-PowerBIRestMethod -Url "https://api.powerbi.com/v1.0/myorg/groups/$workspaceid/datasets/$datasetids/refreshes" -Method Post -Body $refresh -ContentType $content -Verbose
}

# Workspace PowerBI Portal URL 
Write-Output "https://app.powerbi.com/groups/$workspaceid/list"
Write-Output "$sqlserver"
