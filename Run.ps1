[CmdLetBinding()]
Param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]
    $Image = "mcr.microsoft.com/azuredocs/aci-helloworld:latest",

    [Parameter()]
    [ValidateRange(1, 50)]
    [int]
    $Groups = 2,

    [Parameter()]
    [ValidateRange(1, 50)]
    [int]
    $ContainerPerGroup = 1,

    [Parameter()]
    [ValidateRange(1, 4)]
    [int]
    $CpusPerGroup = 2,

    [Parameter()]
    [ValidateRange(1, 16)]
    [int]
    $MemoryGbPerGroup = 4,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]
    $Location = "northeurope"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

$runId = [System.Guid]::NewGuid().ToString().Replace("-", "")
$resourceGroup = "load-generator-$($runId)"
$imageTemporaryName = "load-generator-image-$($runId)"

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

if (-not (Get-Command Connect-AzAccount -errorAction SilentlyContinue)) {
    throw "Az powershell module not installed / or not imported. Check https://docs.microsoft.com/en-us/powershell/azure/install-az-ps"
}

if (-not (Get-Command docker -errorAction SilentlyContinue)) {
    throw "Docker not installed or not available in PATH."
}

$imageExists = docker images -q $Image

if (-not $imageExists) {
    throw "Could not find image $Image from local cache. If you are trying to use public image first run 'docker pull $Image'. If using locally built image check images with 'docker images'"
}

$currentContext = Get-AzContext

Write-Host "Running commands as: $($currentContext.Name)" -ForegroundColor Green

if(-not $currentContext.Name)
{
    throw "Current account not found, have you ran 'Connect-AzAccount'?"
}

Write-Host "Creating resource group $resourceGroup"
New-AzResourceGroup -Name $resourceGroup -Location $Location | Out-Null

$adhocRegistry = New-AzContainerRegistry -ResourceGroupName $resourceGroup -Name "acr$($runId)" -EnableAdminUser -Sku Basic
$creds = Get-AzContainerRegistryCredential -Registry $adhocRegistry
$creds.Password | docker login $adhocRegistry.LoginServer -u $creds.Username --password-stdin

$fullTemporaryImageName = "$($adhocRegistry.LoginServer)/$imageTemporaryName"

docker tag $Image $fullTemporaryImageName
docker push $fullTemporaryImageName
docker logout $adhocRegistry.LoginServer

# These are actually simpler to deploy with command line commands
# without arm. However currently container groups doesn't support
# multiple container images without ARM templates and for this reason
# all parts are deployed using same routine.
# Multiple containers are very usefull since it helps to optimize load generator per
# group. For example in case of selenium even 1CPU/1GB is overkill and it can run multiple instances concurrently.
RunArm (Resolve-Path $PSScriptRoot/arm/container-group.json) -parameters @{
    groupIndex       = @{ value = 1 };
    containerCount   = @{ value = 2 };
    containerImage   = @{ value = $fullTemporaryImageName };
    registryServer   = @{ value = $adhocRegistry.LoginServer };
    registryUsername = @{ value = $creds.Username };
    registryPassword = @{ value = $creds.Password };
}
