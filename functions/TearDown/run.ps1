# Input bindings are passed in via param block.
param($Timer)

if (-not ($env:APPSETTING_ResourceGroupId)) {
    throw "env:APPSETTING_ResourceGroupId not set, aborting."
}

$resourceGroup = Get-AzResourceGroup -Id $env:APPSETTING_ResourceGroupId

if (-not ($env:APPSETTING_ResourceGroupId)) {
    throw "ASSERT: Could not found resource group $env:APPSETTING_ResourceGroupId, this should really never since this app should exist on it by itself."
}

function IsTTLOver { [datetime]::Parse($resourceGroup.Tags.Created).AddMinutes($resourceGroup.Tags.TTLMinutes).ToUniversalTime() -lt [datetime]::UtcNow }

if (IsTTLOver) {
    Remove-AzResourceGroup -Id $env:APPSETTING_ResourceGroupId -Force
}
else {
    Write-Host "TTL of resource group isn't yet met. Skip removal."
}
