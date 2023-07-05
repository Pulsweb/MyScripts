# =================================================================================================================================================
# Best Practice Analyzer for Workspace with XMLA Endpoint
# Romain Casteres - Microsoft Customer Engineer Data & AI - http://pulsweb.fr/
# Inspirations & Thanks :
# - Tabular Editor : https://docs.tabulareditor.com/Best-Practice-Analyzer.html
# - Michael Kovalsky : https://powerbi.microsoft.com/en-us/blog/best-practice-rules-to-improve-your-models-performance/
# - Dave Ruijter : https://www.moderndata.ai/2020/09/check-the-quality-of-all-power-bi-data-models-at-once-with-best-practice-analyzer-automation-bpaa/
# =================================================================================================================================================

# Parameters
$ConnectionMode = 2 # 1 for SSPI | 2 for Login and Password | 3 for Service Principal
$PowerBIServicePrincipalTenantId = "###"
$PowerBIServicePrincipalClientId = "###"
$PowerBIServicePrincipalSecret = "###"
$PowerBIUserId = "###" 
$PowerBIPassword = "###"
$OutputDirectory = "C:\temp\"
$TabularEditorPortableExePath = "C:\Program Files (x86)\Tabular Editor\TabularEditor.exe"
$PremiumWokspaceNameToBeAnalyzed = "###" #PREMIUM REQUIRED
$TabularEditorBPARulesPath = "https://raw.githubusercontent.com/microsoft/Analysis-Services/master/BestPracticeRules/BPARules.json"
$biglistofdatasets = [System.Collections.ArrayList]::new()
$CurrentDateTime = (Get-Date).tostring("yyyyMMdd-HHmmss")
$OutputDir = Join-Path -Path $OutputDirectory -ChildPath "\$CurrentDateTime"
new-item $OutputDir -itemtype directory -Force | Out-Null

# Download BPA Rules
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
wget $TabularEditorBPARulesPath -outfile $OutputDir"\Rules.json"

# Runctions to call the .exe - Author: https://mnaoumov.wordpress.com/
function Test-CalledFromPrompt {
    (Get-PSCallStack)[-2].Command -eq "prompt"
}
function Invoke-NativeApplication {
    param (
        [ScriptBlock] $ScriptBlock,
        [int[]] $AllowedExitCodes = @(0),
        [switch] $IgnoreExitCode
    )
    $backupErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        if (Test-CalledFromPrompt) {
            $lines = & $ScriptBlock
        } else {
            $lines = & $ScriptBlock 2>&1
        }
        $lines | ForEach-Object -Process {
            $isError = $_ -is [System.Management.Automation.ErrorRecord]
            "$_" | Add-Member -Name IsError -MemberType NoteProperty -Value $isError -PassThru
        }
        if ((-not $IgnoreExitCode) -and ($AllowedExitCodes -notcontains $LASTEXITCODE)){
            throw "Execution failed with exit code $LASTEXITCODE"
        }
    }
    finally{
        $ErrorActionPreference = $backupErrorActionPreference
    }
}

# Connection
IF ($WithServicePrincipal -eq "True") {
    Write-Host "Connecting with Service Principal..."
    $secureServicePrincipalSecretBis = $PowerBIServicePrincipalSecret | ConvertTo-SecureString -AsPlainText -Force
    $credential = New-Object PSCredential -ArgumentList $PowerBIServicePrincipalClientId, $secureServicePrincipalSecretBis 
    Connect-PowerBIServiceAccount -ServicePrincipal -Credential $credential -Tenant $PowerBIServicePrincipalTenantId 
} ELSE {
    Write-Host "Connecting to the service..."
    Connect-PowerBIServiceAccount 
}

# BPA for every Datasets within the Workspace 
$workspaces = Get-PowerBIWorkspace -Name $PremiumWokspaceNameToBeAnalyzed
if ($workspaces) {
    $workspacesOutputPath = Join-Path -Path $OutputDirectory -ChildPath "\$CurrentDateTime\Workspaces.json"
    $workspaces | ConvertTo-Json -Compress | Out-File -FilePath $workspacesOutputPath
    $workspaces | Where-Object {$_.IsOnDedicatedCapacity -eq $True} | ForEach-Object {
        $workspaceName = $_.Name
        $worskpaceId = $_.Id
        Write-Host "Premium workspace: $workspaceName"
        $datasets = Get-PowerBIDataset -WorkspaceId $_.Id | Where-Object {$_.Name -ne "Report Usage Metrics Model"}
        $datasets | Add-Member -MemberType NoteProperty -Name "WorkspaceId" -Value $worskpaceId
        $biglistofdatasets += $datasets
        if ($datasets) {
            $datasets | ForEach-Object {
                $datasetName = $_.Name
                Write-Host "- Dataset: $datasetName"
                $DatasetTRXOutputDir = Join-Path -Path $OutputDirectory -ChildPath "\$CurrentDateTime\"
                new-item $DatasetTRXOutputDir -itemtype directory -Force | Out-Null 
                $DatasetTRXOutputPath = Join-Path -Path $DatasetTRXOutputDir -ChildPath "\$workspaceName - $datasetName.trx"
                Write-Host "--- Performing Best Practice Analyzer on dataset: $datasetName."
                Write-Host "--- Output saved: $DatasetTRXOutputPath."
                Switch ($ConnectionMode){
                    1 {
                        Write-Host "----- Connecting with SSPI"
                        Invoke-NativeApplication { cmd /c """$TabularEditorPortableExePath"" ""Provider=MSOLAP;Data Source=powerbi://api.powerbi.com/v1.0/myorg/$workspaceName;Integrated Security=SSPI;"" ""$datasetName"" -A ""$TabularEditorBPARulesPath"" -TRX ""$DatasetTRXOutputPath""" } @(0, 1) $True | Out-Null  
                    }
                    2 {
                        Write-Host "----- Connecting with Login and Password"
                        Invoke-NativeApplication { cmd /c """$TabularEditorPortableExePath"" ""Provider=MSOLAP;Data Source=powerbi://api.powerbi.com/v1.0/myorg/$workspaceName;User ID=$PowerBIUserId;Password=$PowerBIPassword;"" ""$datasetName"" -A ""$TabularEditorBPARulesPath"" -TRX ""$DatasetTRXOutputPath""" } @(0, 1) $True | Out-Null		
                    }
                    3 {
                        Write-Host "----- Connecting with Service Principal"
                        Invoke-NativeApplication { cmd /c """$TabularEditorPortableExePath"" ""Provider=MSOLAP;Data Source=powerbi://api.powerbi.com/v1.0/myorg/$workspaceName;User ID=app:$PowerBIServicePrincipalClientId@$PowerBIServicePrincipalTenantId;Password=$($credential.getNetworkCredential().password)"" ""$datasetName"" -A ""$TabularEditorBPARulesPath"" -TRX ""$DatasetTRXOutputPath""" } @(0, 1) $True | Out-Null
                    }
                }
            }
        }
    }
    Write-Host "Finished on workspace: $workspaceName."
}
$datasetsOutputPath = Join-Path -Path $OutputDirectory -ChildPath "\$CurrentDateTime\Datasets.json"
$biglistofdatasets | ConvertTo-Json -Compress | Out-File -FilePath $datasetsOutputPath