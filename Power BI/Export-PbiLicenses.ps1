# Romain Casteres - https://www.pulsweb.fr

$PBIAdminUPN = ""
$PBIAdminPW = ""
$TenantID = ""

$SecPasswd = ConvertTo-SecureString $PBIAdminPW -AsPlainText -Force
$myCred = New-Object System.Management.Automation.PSCredential($PBIAdminUPN,$SecPasswd)
Connect-AzureAD -TenantId $TenantID -Credential $myCred

$RetrieveDate = Get-Date 
$BasePath = "C:\Users\romainca\Desktop\PBI Licences\"
$AzureADUsersCSV = $BasePath + "LicencesUsers.csv"
$OrgO365LicensesCSV = $BasePath + "LicensesOrgO365.csv"
$UserPBIProLicensesCSV = $BasePath + "LicensesUserPBIPro.csv"

$PBIProServicePlanID = "70d33638-9c74-4d01-bfd3-562de28bd4ba"

Write-Host "Retrieve and export users"
$ADUsers = Get-AzureADUser -All $true | Select-Object ObjectId, ObjectType, CompanyName, Department, DisplayName, Mail, UserPrincipalName, UserType, @{Name="Date Retrieved";Expression={$RetrieveDate}}
0..($ADUsers.count-1) | foreach {
    $percent = ($_/$ADUsers.count)*100
    Write-Progress -Activity 'Retrieve and export users to CSV' -Status "$percent % Complete" -CurrentOperation "Exporting item # $($_+1)" -PercentComplete $percent
    $ADUsers[$_]
} | Export-Csv $AzureADUsersCSV -NoTypeInformation -Force

Write-Host "Retrieve and export organizational licenses"
$OrgO365Licenses = Get-AzureADSubscribedSku | Select-Object SkuID, SkuPartNumber,CapabilityStatus, ConsumedUnits -ExpandProperty PrepaidUnits | `
    Select-Object SkuID,SkuPartNumber,CapabilityStatus,ConsumedUnits,Enabled,Suspended,Warning, @{Name="Retrieve Date";Expression={$RetrieveDate}} 
0..($OrgO365Licenses.count-1) | foreach {
    $percent = ($_/$OrgO365Licenses.count)*100
    Write-Progress -Activity 'Retrieve and export organizational licenses to CSV' -Status "$percent % Complete" -CurrentOperation "Exporting item # $($_+1)" -PercentComplete $percent 
    $OrgO365Licenses[$_]
} | Export-Csv $OrgO365LicensesCSV -NoTypeInformation -Force

Write-Host "Retrieve and export users with pro licenses based on Power BI Pro service plan ID"
$ProUsersCounter = 0
$ProUsersCount = $ADUsers.Count 
$UserLicenseDetail = ForEach ($ADUser in $ADUsers){
        $UserObjectID = $ADUser.ObjectId
        $UPN = $ADUser.UserPrincipalName
        Get-AzureADUserLicenseDetail -ObjectId $UserObjectID -ErrorAction SilentlyContinue | `
            Select-Object ObjectID, @{Name="UserPrincipalName";Expression={$UPN}} -ExpandProperty ServicePlans
        Write-Progress -Activity "Retreiving users licences, set `$Licences to `$False and rerun the script" -PercentComplete ($ProUsersCounter * 100.0/$ProUsersCount)
        $ProUsersCounter += 1
}
$ProUsers = $UserLicenseDetail | Where-Object {$_.ServicePlanId -eq $PBIProServicePlanID}
$ProUsers | Export-Csv $UserPBIProLicensesCSV -NoTypeInformation -Force