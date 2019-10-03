# Romain Casteres - https://www.pulsweb.fr

# The output folder to put all the extracts in
$folder = "out"
$folderFullPath = "$PSScriptRoot\$folder"

If(!(test-path $folderFullPath))
{
      New-Item -ItemType Directory -Force -Path $folderFullPath
}

# Installing Connect-AzureAD if not present
if (Get-Module -ListAvailable -Name "AzureAD") {
    Write-Host "Connect-AzureAD Module exists"
} else {
    Write-Host "Connect-AzureAD Module does not exist  - Installing it..."
    Install-Module AzureAD
}

# Connect to Azure with a Prompt
Connect-AzureAD

# Collect license info
$PBILicenses = Get-AzureADSubscribedSku | Where-Object{$_.SkuPartNumber -like '*POWER_BI*' -and $_.CapabilityStatus -eq 'Enabled'} | Select-Object SkuPartNumber, ConsumedUnits, SkuId

# Return global license count
# $PBILicenses | Select-Object SkuPartNumber, ConsumedUnits, SkuId

$PBIUsers = @()
# Loop through each license and list all users
foreach($license in $PBILicenses) {
    $PBIUsers += Get-AzureADUser -All $True | Where-Object{($_.AssignedLicenses | Where-Object{$_.SkuId -eq $license.SkuId})} | Select-Object DisplayName, UserPrincipalName, @{l='License';e={$license.SkuPartNumber}}
}

# Output to CSV
$PBIUsers | Export-Csv $folderFullPath + "PowerBI-Licenses.csv" -NoTypeInformation -Force