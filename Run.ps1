<#
.SYNOPSIS

Creates array of containers to generate load with Azure ACI.

.DESCRIPTION

When creating load tests you need docker, powershell 6.2+ and powershell AZ installed.
See examples and documentation how tool can be used.

Please don't run this on production Azure environment: script contains tear-down functionalities
that remove resources automatically. There should be no risk anything else will be removed but
authors of this tools will not take any responsibility if you run it on production environment.

.EXAMPLE

PS> ./Run.ps1 -Image "somelocalimage"

.EXAMPLE

PS> ./Run.ps1 -Image "somelocalimage" -TTLInMinutes 30 -Groups 3 -ContainerPerGroup 3

#>
[CmdLetBinding()]
Param(

    # Image name from local cache that contains load generator software.
    # For example use 'example' app, build it locally with tag 'loadtest' and
    # give parameter 'loadtest' for Image parameter. If you use image from external
    # repository you must first pull it to local cache with 'docker pull'.
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Image,

    # Generating load can require lots of resources and they are pretty expensive
    # if they are not cleaned up correctly. For this reason tool has automatic tear-down
    # functionality that removes all resources used automatically after this TTL period is over.
    # Defaults to 60 minutes and can be set up to 6 hours.
    [Parameter()]
    [ValidateRange(5, 60*6)]
    [int]
    $TTLInMinutes = 60,

    # Test setup is built from two parts: groups and containers. Group can host multiple
    # containers. This concept is similar to Kubernetes 'pods'.
    # For example 3 groups with 3 containers makes 9 running containers in total.
    # This is divided because there's limits how many groups and containers can be used.
    # There's total 100 group in subscription limit in azure.
    [Parameter()]
    [ValidateRange(1, 50)]
    [int]
    $Groups = 1,

    # How many containers each group will run. Containers share certain resources
    # similar to containers in 'pods' at kubernetes.
    # Each group can have up to 60 containers which is the hard limit for Azure.
    [Parameter()]
    [ValidateRange(1, 60)]
    [int]
    $ContainerPerGroup = 1,

    # CPU per container. It's important to notice that the total capacity neededed for group
    # is calculated container_count*cpu. For example 3 containers with 1 cpu = 3 cpus.
    # See exact limits https://docs.microsoft.com/bs-latn-ba/azure/container-instances/container-instances-region-availability?view=azuremgmtcdn-fluent-1.0.0#availability---general
    [Parameter()]
    [ValidateRange(0.1, 4)]
    [decimal]
    $CpusPerContainer = 1,

    # Memory per container. It's important to notice that the total capacity neededed for group
    # is calculated container_count*memory. For example 3 containers with 1 GB each = 3 GB.
    # See exact limits https://docs.microsoft.com/bs-latn-ba/azure/container-instances/container-instances-region-availability?view=azuremgmtcdn-fluent-1.0.0#availability---general
    [Parameter()]
    [ValidateRange(0.1, 16)]
    [decimal]
    $MemoryPerContainerGb = 1,

    # Theres may be policies in targeted environment that enforces certain metadata customer/project names etc or you maybe just want to add information about test run to
    # resource group metada.
    [Parameter()]
    [hashtable]
    $Tags = @{},

    # Desired geo-location of resource group.
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

$imageId = docker images -q $Image

if (-not $imageId) {
    throw "Could not find image $Image from local cache. If you are trying to use public image first run 'docker pull $Image'. If using locally built image check images with 'docker images'"
}

if($imageId -is [array]) {
    throw "Find more than one local image matching $Image, add correct tag for image and try again."
}

$currentContext = Get-AzContext

Write-Host "Running commands as: $($currentContext.Name)" -ForegroundColor Green

if (-not $currentContext.Name) {
    throw "Current account not found, have you ran 'Connect-AzAccount'?"
}

if ($ContainerPerGroup * $CpusPerContainer -gt 4) {
    throw "Total CPU:s in group can be maximum of 4. Total per group is container count * cpu:s. See more information from https://docs.microsoft.com/en-us/azure/container-instances/container-instances-region-availability"
}

if ($ContainerPerGroup * $CpusPerContainer -gt 16) {
    throw "Total memory in group can be maximum of 16GB. Total per group is container count * memory. See more information from https://docs.microsoft.com/en-us/azure/container-instances/container-instances-region-availability"
}

$confirmation = Read-Host "Are you sure you want to create new resource group $resourceGroup in context [$($currentContext.Name), tenant: $($currentContext.Tenant)] and start load? [y/n]"

if ($confirmation.ToLower() -ne "y") {
    exit
}

Write-Host "Creating resource group $resourceGroup" -ForegroundColor Green

$Tags["Created"] = ([datetime]::UtcNow.ToString("o"))
$Tags["TTLMinutes"] = $TTLInMinutes

New-AzResourceGroup -Name $resourceGroup -Location $Location -Tags $Tags | Out-Null

Write-Host "Creating automatic tear down function for resource group, triggers after $TTLInMinutes minutes (TTLInMinutes)." -ForegroundColor Green

$functionAppOutputs = RunArm (Resolve-Path $PSScriptRoot/arm/function-app.json)
New-AzRoleAssignment -ObjectId $functionAppOutputs.Outputs.principalId.Value -RoleDefinitionName "Contributor" -Scope "/subscriptions/$($functionAppOutputs.Outputs.subscriptionId.Value)/resourceGroups/$resourceGroup/" | Out-Null

$temporaryFolderForZip = Join-Path ([System.IO.Path]::GetTempPath()) -ChildPath ([Guid]::NewGuid())
Copy-Item ./functions/ $temporaryFolderForZip -Recurse -Force | Out-Null
Remove-Item $temporaryFolderForZip/local.settings.json -Recurse -Force | Out-Null

Compress-Archive -Path $temporaryFolderForZip/* -DestinationPath $PSScriptRoot/functions.deployment.zip -Force | Out-Null
Publish-AzWebApp -ResourceGroupName $resourceGroup -Name $functionAppOutputs.Outputs.appName.Value -ArchivePath $PSScriptRoot/functions.deployment.zip -Force | Out-Null

Write-Host "Uploading image '$Image' to temporary container registry from local computer." -ForegroundColor Green

$adhocRegistry = New-AzContainerRegistry -ResourceGroupName $resourceGroup -Name "acr$($runId)" -EnableAdminUser -Sku Basic
$creds = Get-AzContainerRegistryCredential -Registry $adhocRegistry
$creds.Password | docker login $adhocRegistry.LoginServer -u $creds.Username --password-stdin

$fullTemporaryImageName = "$($adhocRegistry.LoginServer)/$imageTemporaryName"

Write-Host "Pushing image '$Image' ($imageId) from local cache." -ForegroundColor Green

docker tag $imageId $fullTemporaryImageName
docker push $fullTemporaryImageName
docker logout $adhocRegistry.LoginServer

Write-Host "Creating $Groups groups with $ContainerPerGroup containers running load in each. This totals $($Groups*$ContainerPerGroup) agents total." -ForegroundColor Green

foreach ($groupIndex in 1..$Groups) {
    Write-Host "Creating container group $groupIndex of $Groups"

    # These are actually simpler to deploy with command line commands
    # without arm. However currently container groups doesn't support
    # multiple container images without ARM templates and for this reason
    # all parts are deployed using same routine.
    # Multiple containers are very usefull since it helps to optimize load generator per
    # group. For example in case of selenium even 1CPU/1GB is overkill and it can run multiple instances concurrently.
    RunArm (Resolve-Path $PSScriptRoot/arm/container-group.json) -parameters @{
        groupIndex       = @{ value = $groupIndex };
        containerCount   = @{ value = $ContainerPerGroup };
        containerImage   = @{ value = $fullTemporaryImageName };
        registryServer   = @{ value = $adhocRegistry.LoginServer };
        registryUsername = @{ value = $creds.Username };
        registryPassword = @{ value = $creds.Password };
        cpus             = @{ value = $CpusPerContainer.ToString("f", [CultureInfo]::InvariantCulture) };
        memoryGb         = @{ value = $MemoryPerContainerGb.ToString("f", [CultureInfo]::InvariantCulture) };
    } | Out-Null
}

Write-Host "Load generator is running on resource group $resourceGroup, see created resources with 'Get-AzResource -ResourceGroupName $resourceGroup'" -ForegroundColor Green
