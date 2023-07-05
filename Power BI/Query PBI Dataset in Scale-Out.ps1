[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.AnalysisServices.AdomdClient") 

$PowerBILogin = "###"
$PowerBIPassword = "###"
$Query = "Evaluate Query1"

$PowerBIEndpoint = "powerbi://api.powerbi.com/v1.0/myorg/RCA_ScaleOut?readonly;initial catalog=ScaleOut_Test"
$Connection = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection
$Results = New-Object System.Data.DataTable
$Connection.ConnectionString = "Datasource="+ $PowerBIEndpoint +";UID="+ $PowerBILogin +";PWD="+ $PowerBIPassword  
$Connection.Open()
$Adapter = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdDataAdapter $Query ,$Connection
$Adapter.Fill($Results)
$Results
$Connection.Dispose()
$Connection.Close()

$PowerBIEndpoint = "powerbi://api.powerbi.com/v1.0/myorg/RCA_ScaleOut?readwrite;initial catalog=ScaleOut_Test"
$Connection = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection
$Results = New-Object System.Data.DataTable
$Connection.ConnectionString = "Datasource="+ $PowerBIEndpoint +";UID="+ $PowerBILogin +";PWD="+ $PowerBIPassword  
$Connection.Open()
$Adapter = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdDataAdapter $Query ,$Connection
$Adapter.Fill($Results)
$Results
$Connection.Dispose()
$Connection.Close()
