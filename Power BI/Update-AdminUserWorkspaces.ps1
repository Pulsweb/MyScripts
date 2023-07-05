# Romain Casteres - https://www.PulsWeb.fr
# Following script is adding users as admin of all workspaces [Administrator rights required]
# "A person with a Power BI Pro license can be a member of a maximum 1,000 workspaces" Source : https://docs.microsoft.com/en-us/power-bi/collaborate-share/service-new-workspaces#limitations-and-considerations

$UserMail = "###@###"

$folder = "out"
$folderFullPath = "$PSScriptRoot\$folder"
If(!(test-path $folderFullPath)){
      New-Item -ItemType Directory -Force -Path $folderFullPath
}
$FileName = "$folderFullPath\UpdatedWorkspaces.csv"
if (Test-Path $FileName) {
    Remove-Item $FileName
}

# Installing PbiAdminModules if not present
if (Get-Module -ListAvailable -Name "MicrosoftPowerBIMgmt") {
    Write-Host "MicrosoftPowerBIMgmt Module exists"
	#Update-Module MicrosoftPowerBIMgmt
} else {
    Write-Host "MicrosoftPowerBIMgmt Module does not exist  - Installing it..."
    Install-PbiAdminModules
}
Import-Module MicrosoftPowerBIMgmt

Connect-PowerBIServiceAccount

# Get the list of workspaces as a Power BI User and as Admin User
$myWorkspaces = Get-PowerBIWorkspace
$tentantWorkspaces = Get-PowerBIWorkspace -Scope Organization -All
Write-Host “The current user has –” $myWorkspaces.Count “– workspaces. There are –” $tentantWorkspaces.Count “– workspaces in this Power BI tenant.”

# Get the list of all workspaces and add Uset as Admin
$Groups = Get-PowerBIWorkspace -Scope Organization -All # -First 5
$Groups = $Groups | SELECT Id, Name, Type, State, Users | WHERE State -NE 'Deleted' 
#FILTER ON PERSONAL WORKSPACE
$GroupWorkspaces = $Groups | WHERE Type -eq 'Workspace' 
$GroupWorkspaces | ForEach-Object {
    if($_.Users.UserPrincipalName -contains $UserMail) {
        Write-Host $UserMail "is already administrator of the" $_.Id "Workspace"
    } else {
        Write-Host "Adding" $UserMail "as administrator of the" $_.Id "Workspace"
        Add-PowerBIWorkspaceUser -Scope Organization -Id $_.Id -UserEmailAddress $UserMail -AccessRight Admin -WarningAction Ignore
        New-Object PSObject -Property @{ 
            Id = $_.Id; 
            Name = $_.Name;  
        } 
    }    
} | Export-CSV $FileName -NoTypeInformation -Encoding UTF8 -Force

# Get the list of workspaces as a Power BI User and as Admin User
$myWorkspaces = Get-PowerBIWorkspace
$tentantWorkspaces = Get-PowerBIWorkspace -Scope Organization -All
Write-Host “The current user has –” $myWorkspaces.Count “– workspaces. There are –” $tentantWorkspaces.Count “– workspaces in this Power BI tenant.”

Disconnect-PowerBIServiceAccount