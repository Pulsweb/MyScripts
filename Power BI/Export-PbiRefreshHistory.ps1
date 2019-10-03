# Romain Casteres - https://www.pulsweb.fr

# The output folder to put all the extracts
$folder = "out"
$folderFullPath = "$PSScriptRoot\$folder"

If(!(test-path $folderFullPath)){
      New-Item -ItemType Directory -Force -Path $folderFullPath
}

# Installing PbiAdminModules if not present
if (Get-Module -ListAvailable -Name "MicrosoftPowerBIMgmt") {
    Write-Host "MicrosoftPowerBIMgmt Module exists"
} else {
    Write-Host "MicrosoftPowerBIMgmt Module does not exist  - Installing it..."
    Install-PbiAdminModules
}

# Prompt the user for credentials
$credential = (Get-Credential -Message "Credentials")

# Log in to Power BI
Login-PowerBIServiceAccount -Credential $credential

# Store the Auth token
$auth = (Get-PowerBIAccessToken).Authorization

Write-Host 'Building Rest API header with authorization token'
$authHeader = @{
    'Content-Type'='application/json'
    'Authorization'='Bearer ' + $auth
}

$TopN = 50
$headers = @{
    "Authorization" = $auth;
    "X-PowerBI-User-Admin" = $true
}

$FileName = "$folderFullPath\PowerBI-RefreshHistory.csv"
if (Test-Path $FileName) {
    Remove-Item $FileName
}

$workspaces = Get-PowerBIWorkspace

foreach($workspaces in $workspaces){
    
    Write-Host "> Workspace: $($workspaces.Name)"
    
    $datasets = Get-PowerBIDataset -WorkspaceId $workspaces.Id

    $refreshes = @()

    foreach($dataset in $datasets){

        if($dataset.IsRefreshable -eq "True") {

            Write-Host ">> Dataset: $($dataset.name)"

            $uri = "https://api.powerbi.com/v1.0/myorg/groups/$($workspaces.Id)/datasets/$($dataset.id)/refreshes/?`$top=$($TopN)"
                               
            $refresh = Invoke-RestMethod -Uri $uri -Headers $headers -Method GET                
            $refresh.value | Add-Member -NotePropertyName "DatasetID" -NotePropertyValue $dataset.id 
            $refresh.value | Add-Member -NotePropertyName "DatasetName" -NotePropertyValue $dataset.name 
            $refresh.value | Add-Member -NotePropertyName "WorkspaceID" -NotePropertyValue $workspaces.Id
            $refreshes += $refresh
        }
    }

    $refreshes.value | ForEach-Object { 
                New-Object PSObject -Property @{ 
                    id = $_.id; 
                    refreshType = $_.refreshType;  
                    startTime = $_.startTime;
                    endTime = $_.endTime;
                    serviceExceptionJson = $_.serviceExceptionJson;
                    status = $_.status;
                    DatasetID = $_.DatasetID;
                    DatasetName = $_.DatasetName;
                    WorkspaceID = $_.WorkspaceID;
                } 
            } | Export-Csv -Path $FileName -NoTypeInformation -Append
}
