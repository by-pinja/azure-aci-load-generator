[CmdLetBinding()]
Param()

$resourceGroup = "load-generator-$([System.Guid]::NewGuid())"

$passwordForRegistry = [System.Guid]::NewGuid()

$registryPassword = ConvertTo-SecureString $passwordForRegistry -AsPlainText -Force
$credsForRegistry = New-Object System.Management.Automation.PSCredential ("myacr", $registryPassword)

function CreateResourceGroup {
    $resourceGroupArm = Resolve-Path "$PSScriptRoot/arm/resource-group.json"
    $resourceGroupParameters = @{ groupName = $resourceGroup }

    New-AzDeployment `
        -Name ([System.IO.Path]::GetFileName($resourceGroupArm)) `
        -TemplateFile $resourceGroupArm `
        -Location "northeurope" `
        -TemplateParameterObject $resourceGroupParameters | Out-Null
}

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

CreateResourceGroup
RunArm (Resolve-Path $PSScriptRoot/arm/container-group.json)