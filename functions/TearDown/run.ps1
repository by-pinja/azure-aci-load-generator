# Input bindings are passed in via param block.
param($Timer)

$resourceGroup = Get-AzResourceGroup -Name "load-generator-tear-down-test"

function [bool]IsTTLOver{ [datetime]::Parse($resourceGroup.Tags.Created).AddMinutes($resourceGroup.Tags.TTLMinutes).ToUniversalTime() -gt [datetime]::UtcNow }

if (IsTTLOver) {
    Write-Host "Delete it now."
}