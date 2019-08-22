$resourceGroup = "load-generator-tear-down-test"
$Location = "northeurope"

New-AzResourceGroup -Name $resourceGroup -Location $Location -Tag @{Created=([datetime]::UtcNow.ToString("o")); TTLMinutes=(5)} | Out-Null

function RunArm([string] $file, $parameters) {
    $file = Resolve-Path $file

    # Use temporary parameter file. This is because 'TemplateParameterObject' expects
    # hashtable which isn't problem by itself. But when parameters that are fetched from files like (deployment.json)
    # they are PsCustomObjects as default and are deeply nested in cases like route tables. Only option is
    # either recursively re-create object as hashtable or use temporary file.
    # Using mixed object causes errors like there was properties like "CliXml", happy debugging and new year for you too ":D".
    $tempFile = [System.IO.Path]::GetTempFileName()
    ($parameters, @{ } -ne $null)[0] | ConvertTo-Json -Depth 10 | Set-Content $tempFile | Out-Null

    Write-Host "Running arm template '$file' with parameters '$($parameters | ConvertTo-Json -Depth 10 -Compress)', executing with temporary parameters file '$($tempFile)'"

    try {
        New-AzResourceGroupDeployment `
            -Name ([System.IO.Path]::GetFileName($file)) `
            -ResourceGroupName $resourceGroup `
            -TemplateFile $file `
            -TemplateParameterFile $tempFile
    }
    catch {
        Write-Host "If error contains correlation ID you can fetch more information of it with 'Get-AzLog -CorrelationId [correlationId] -DetailedOutput'. It may take while before available." -ForegroundColor Yellow
        throw $_.Exception
    }
}

$functionAppOutputs = RunArm (Resolve-Path $PSScriptRoot/arm/function-app.json)

New-AzRoleAssignment -ObjectId $functionAppOutputs.Outputs.principalId.Value -RoleDefinitionName "Contributor" -Scope "/subscriptions/$($functionAppOutputs.Outputs.subscriptionId.Value)/resourceGroups/$resourceGroup/"

$temporaryFolderForZip = Join-Path ([System.IO.Path]::GetTempPath()) -ChildPath ([Guid]::NewGuid())
Copy-Item ./functions/ $temporaryFolderForZip -Recurse -Force
Remove-Item $temporaryFolderForZip/local.settings.json -Recurse -Force
Remove-Item $temporaryFolderForZip/.vscode/ -Recurse -Force

Compress-Archive -Path $temporaryFolderForZip/* -DestinationPath $PSScriptRoot/functions.deployment.zip -Force
Publish-AzWebApp -ResourceGroupName "load-generator-tear-down-test" -Name "functions-nykr665cektgo" -ArchivePath $PSScriptRoot/functions.deployment.zip -Force