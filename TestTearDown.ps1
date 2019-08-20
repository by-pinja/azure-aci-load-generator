[CmdLetBinding()]
Param()

$resourceGroup = "load-generator-tear-down-test"
$Location = "northeurope"

New-AzResourceGroup -Name $resourceGroup -Location $Location | Out-Null

