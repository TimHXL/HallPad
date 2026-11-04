param(
    [Parameter(Mandatory=$true)][string]$InputFolder,
    [string]$OutputFolder = "$PSScriptRoot\HPG_OUT",
    [int]$Track = -1,
    [string]$Font = ""
)
$ErrorActionPreference = 'Stop'
$arguments = @('-u',"$PSScriptRoot\batch_to_hpg3.py",'--input-folder',$InputFolder,'--output-folder',$OutputFolder,'--track',"$Track")
if ($Font) { $arguments += @('--font',$Font) }
& python @arguments
if ($LASTEXITCODE -ne 0) { throw "Batch setup failed. See the message above." }
