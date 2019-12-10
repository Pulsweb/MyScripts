# Romain Casteres - Analyzing PBIRS Tabular Model Size
# AMO Required (SSAS Feature Pack)
# SSAS Instance for PBIRS : "localhost:5132"

Param($ServerName="localhost:5132")

$loadInfo = [Reflection.Assembly]::LoadWithPartialName("Microsoft.AnalysisServices")

$server = New-Object Microsoft.AnalysisServices.Server
$server.connect($ServerName)

if ($server.name -eq $null) {
    Write-Output (“Server ‘{0}’ not found” -f $ServerName)
    break
}

$sum=0
foreach ($d in $server.Databases ){
    Write-Output ( "Database: {0}; Status: {1}; Size: {2}MB" -f $d.Name, $d.State, ($d.EstimatedSize/1024/1024).ToString("#,##0") )
    $sum=$sum+$d.EstimatedSize/1024/1024
}

$SizeGB=$Sum/1024

write-host 'Sum of Database = '$sum ' MB'
Write-host 'Total Size of Cube Databases =' $SizeGB ' GB'