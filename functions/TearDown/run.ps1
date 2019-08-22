# Input bindings are passed in via param block.
param($Timer)


$env:APPSETTING_ResourceGroupId = "/subscriptions/d480c786-cdcd-4078-8c23-9f882607201a/resourceGroups/load-generator-tear-down-test"


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

