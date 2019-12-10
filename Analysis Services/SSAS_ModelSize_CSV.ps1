# Romain Casteres - Analyzing PBIRS Tabular Model Size
# AMO Required (SSAS Feature Pack)
# SSAS Instance for PBIRS : "localhost:5132"
# Export to CSV

Param($ServerName="localhost:5132")
$loadInfo = [Reflection.Assembly]::LoadWithPartialName("Microsoft.AnalysisServices")

$outputfile = "C:\temp\PBIRS_ModelSize.csv"
if (Test-Path $outputfile) {
    Remove-Item $outputfile
}

$server = New-Object Microsoft.AnalysisServices.Server
$server.connect($ServerName)
if ($server.name -eq $null) {
    Write-Output (“Server ‘{0}’ not found” -f $ServerName)
    break
}

$sum=0
foreach ($d in $server.Databases ){
      New-Object PSObject -Property @{ 
        Name = $d.Name;
        ItemID = $d.Name.SubString(0,36); # Mapping to the ItemID column from Catalog table
        SizeMB = [math]::Round($d.EstimatedSize/1024/1024,2); 
      } | export-csv -Path $outputfile -NoTypeInformation -Append
} 
