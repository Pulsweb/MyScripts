<#
.SYNOPSIS
    Extracts all Dataflow Gen1 from a Fabric/Power BI tenant with upstream info.

.DESCRIPTION
    Authenticates interactively as a Fabric administrator and exports a CSV with:
    Dataflow Name, Dataflow Id, Workspace Name, Workspace Id,
    computeEngineBehavior, Upstream Dataflow Name, Upstream Dataflow Id,
    Upstream Workspace Name, Upstream Workspace Id

.PARAMETER OutputCsvPath
    Path for the output CSV. Defaults to .\DataflowsReport_<timestamp>.csv

.PARAMETER DelayBetweenCallsMs
    Delay in ms between upstream API calls (default 200).
    Raise to 18000 if you have 190+ dataflows to stay under the 200 req/hr limit.

.NOTES
    Requires: MicrosoftPowerBIMgmt module
    Install:  Install-Module MicrosoftPowerBIMgmt -Scope CurrentUser -Force
    Account:  Must be a Fabric Administrator
#>
[CmdletBinding()]
param (
    [string]$OutputCsvPath = (Join-Path $PSScriptRoot ("DataflowsReport_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".csv")),
    [int]$DelayBetweenCallsMs = 200
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 0. Ensure module is present
# ---------------------------------------------------------------------------
$moduleName = 'MicrosoftPowerBIMgmt'
if (-not (Get-Module -ListAvailable -Name $moduleName)) {
    Write-Host "Module '$moduleName' not found. Installing..." -ForegroundColor Yellow
    Install-Module -Name $moduleName -Scope CurrentUser -Force -AllowClobber
    Write-Host "Module installed." -ForegroundColor Green
}
Import-Module $moduleName -ErrorAction Stop

# ---------------------------------------------------------------------------
# 1. Interactive login
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "[1/6] Connecting to Power BI Service - sign in with your Fabric Admin account..." -ForegroundColor Cyan
$loginResult = Connect-PowerBIServiceAccount
if (-not $loginResult) {
    throw "Authentication failed. Please re-run the script and sign in when prompted."
}
Write-Host "      Connected as: $($loginResult.UserName)" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Helper: call a relative PBI REST URL with 429 retry.
# Invoke-PowerBIRestMethod always returns a raw JSON string.
# ---------------------------------------------------------------------------
function Invoke-PBIWithRetry {
    param(
        [string] $RelUrl,
        [int]    $MaxRetries = 5
    )
    $attempt = 0
    while ($true) {
        try {
            $attempt++
            $raw = Invoke-PowerBIRestMethod -Url $RelUrl -Method Get -ErrorAction Stop
            return ($raw | ConvertFrom-Json)
        }
        catch {
            $code = $null
            if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
            if ($code -eq 429 -and $attempt -le $MaxRetries) {
                $wait = 60
                try { $wait = [int]$_.Exception.Response.Headers['Retry-After'] } catch {}
                $wait = [Math]::Max($wait, [Math]::Pow(2, $attempt) * 10)
                Write-Warning "  429 rate-limit. Waiting $wait s (attempt $attempt/$MaxRetries)..."
                Start-Sleep -Seconds $wait
            }
            else { throw }
        }
    }
}

# ---------------------------------------------------------------------------
# Helper: collect all pages from a paged admin endpoint
# ---------------------------------------------------------------------------
function Get-AllPages {
    param(
        [string] $RelUrl,
        [int]    $PageSize = 5000
    )
    $all  = [System.Collections.Generic.List[object]]::new()
    $skip = 0
    do {
        $resp = Invoke-PBIWithRetry -RelUrl "${RelUrl}?`$top=${PageSize}&`$skip=${skip}"
        # Use @() so a single-item result is always an array
        $page = @($resp.value)
        if ($page.Count -gt 0) { $all.AddRange($page) }
        $skip += $PageSize
    } while ($page.Count -eq $PageSize)
    return $all
}

# ---------------------------------------------------------------------------
# 2. Fetch all workspaces for name resolution
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "[2/6] Fetching all workspaces..." -ForegroundColor Cyan
$workspaces    = Get-AllPages -RelUrl 'admin/groups'
$workspaceById = @{}
foreach ($ws in $workspaces) { $workspaceById[$ws.id] = $ws.name }
Write-Host "      Found $($workspaces.Count) workspaces." -ForegroundColor Green

# ---------------------------------------------------------------------------
# 3. Fetch all Dataflow Gen1 across the tenant (bulk admin endpoint)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "[3/6] Fetching all Dataflow Gen1..." -ForegroundColor Cyan
$allDataflows = Get-AllPages -RelUrl 'admin/dataflows'
Write-Host "      Found $($allDataflows.Count) dataflows." -ForegroundColor Green

if ($allDataflows.Count -gt 190) {
    Write-Warning "Tenant has $($allDataflows.Count) dataflows. Rate limit is 200 req/hr - script will auto-retry on 429."
}

$dataflowById = @{}
foreach ($df in $allDataflows) { $dataflowById[$df.objectId] = $df }

# ---------------------------------------------------------------------------
# 4. Enrich with computeEngineBehavior via per-workspace endpoint.
#    The bulk admin/dataflows endpoint does not return this property.
#    We call groups/{wsId}/dataflows once per workspace that has dataflows.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "[4/6] Enriching computeEngineBehavior per workspace..." -ForegroundColor Cyan

$cebByDataflowId   = @{}
$uniqueWsIds       = @($allDataflows | Select-Object -ExpandProperty workspaceId -Unique)
$wsIdx             = 0

foreach ($wsId in $uniqueWsIds) {
    $wsIdx++
    $wsLabel = if ($workspaceById.ContainsKey($wsId)) { $workspaceById[$wsId] } else { $wsId }
    Write-Progress -Activity "Loading computeEngineBehavior" `
                   -Status "$wsIdx / $($uniqueWsIds.Count)  |  $wsLabel" `
                   -PercentComplete ([Math]::Round(($wsIdx / $uniqueWsIds.Count) * 100))
    try {
        $wsDfs = @((Invoke-PBIWithRetry -RelUrl "groups/$wsId/dataflows").value)
        foreach ($wsDf in $wsDfs) {
            if ($wsDf -and $wsDf.objectId) {
                $ceb = if ($wsDf.PSObject.Properties['computeEngineBehavior'] -and
                            $wsDf.computeEngineBehavior) {
                           $wsDf.computeEngineBehavior
                       } else { 'NotConfigured' }
                $cebByDataflowId[$wsDf.objectId] = $ceb
            }
        }
    }
    catch {
        Write-Warning "  Could not get workspace dataflows for '$wsLabel' [$wsId]: $_"
    }
    Start-Sleep -Milliseconds 100
}
Write-Progress -Activity "Loading computeEngineBehavior" -Completed
Write-Host "      computeEngineBehavior loaded for $($cebByDataflowId.Count) dataflows." -ForegroundColor Green

# ---------------------------------------------------------------------------
# 5. For each dataflow fetch upstream dependencies
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "[5/6] Querying upstream dependencies..." -ForegroundColor Cyan

$results     = [System.Collections.Generic.List[PSCustomObject]]::new()
$idx         = 0
$total       = $allDataflows.Count

foreach ($df in $allDataflows) {
    $idx++
    Write-Progress -Activity "Fetching upstream dataflows" `
                   -Status "$idx / $total  |  $($df.name)" `
                   -PercentComplete ([Math]::Round(($idx / $total) * 100))

    $wsId   = $df.workspaceId
    $wsName = if ($workspaceById.ContainsKey($wsId)) { $workspaceById[$wsId] } else { $wsId }
    $ceb    = if ($cebByDataflowId.ContainsKey($df.objectId)) { $cebByDataflowId[$df.objectId] } else { 'NotConfigured' }

    $upList = @()
    try {
        $upResp = Invoke-PBIWithRetry -RelUrl "admin/groups/$wsId/dataflows/$($df.objectId)/upstreamDataflows"
        # @() ensures single-item results are treated as an array (PS 5.1 quirk)
        $upList = @($upResp.value) | Where-Object { $_ -ne $null }
    }
    catch {
        Write-Warning "  Cannot get upstream for '$($df.name)' [$($df.objectId)]: $_"
    }

    if ($upList.Count -eq 0) {
        $results.Add([PSCustomObject]@{
            'Dataflow Name'           = $df.name
            'Dataflow Id'             = $df.objectId
            'Workspace Name'          = $wsName
            'Workspace Id'            = $wsId
            'computeEngineBehavior'   = $ceb
            'Upstream Dataflow Name'  = ''
            'Upstream Dataflow Id'    = ''
            'Upstream Workspace Name' = ''
            'Upstream Workspace Id'   = ''
        })
    }
    else {
        foreach ($up in $upList) {
            $upDf     = if ($dataflowById.ContainsKey($up.targetDataflowId)) { $dataflowById[$up.targetDataflowId] } else { $null }
            $upDfName = if ($upDf) { $upDf.name } else { $up.targetDataflowId }
            $upWsId   = $up.groupId
            $upWsName = if ($workspaceById.ContainsKey($upWsId)) { $workspaceById[$upWsId] } else { $upWsId }
            $results.Add([PSCustomObject]@{
                'Dataflow Name'           = $df.name
                'Dataflow Id'             = $df.objectId
                'Workspace Name'          = $wsName
                'Workspace Id'            = $wsId
                'computeEngineBehavior'   = $ceb
                'Upstream Dataflow Name'  = $upDfName
                'Upstream Dataflow Id'    = $up.targetDataflowId
                'Upstream Workspace Name' = $upWsName
                'Upstream Workspace Id'   = $upWsId
            })
        }
    }

    if ($DelayBetweenCallsMs -gt 0 -and $idx -lt $total) {
        Start-Sleep -Milliseconds $DelayBetweenCallsMs
    }
}
Write-Progress -Activity "Fetching upstream dataflows" -Completed

# ---------------------------------------------------------------------------
# 6. Export and display summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "[6/6] Exporting results..." -ForegroundColor Cyan
$results | Export-Csv -Path $OutputCsvPath -NoTypeInformation -Encoding UTF8

$withUpstream    = @($results | Where-Object { $_.'Upstream Dataflow Id' -ne '' })
$upstreamCount   = $withUpstream.Count

Write-Host ""
Write-Host "---------------------------------------------" -ForegroundColor DarkGray
Write-Host " Run complete" -ForegroundColor Green
Write-Host "---------------------------------------------" -ForegroundColor DarkGray
Write-Host "  Dataflows found   : $($allDataflows.Count)"
Write-Host "  Result rows (CSV) : $($results.Count)"
Write-Host "  Rows with upstream: $upstreamCount"
Write-Host "  Output file       : $OutputCsvPath" -ForegroundColor Green
Write-Host "---------------------------------------------" -ForegroundColor DarkGray

if ($upstreamCount -gt 0) {
    Write-Host ""
    Write-Host "Dataflows with upstream dependencies ($upstreamCount rows):" -ForegroundColor Cyan
    $withUpstream | Format-Table -AutoSize -Wrap
} else {
    Write-Host ""
    Write-Host "NOTE: No upstream linked-entity dependencies found." -ForegroundColor Yellow
}