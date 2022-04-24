param($Location, $Env, $Name)

$params = @{
    location = $Location
    env = $Env
    projectName = $Name
}

New-AzDeployment -Location $Location -TemplateFile './resourceGroup.bicep' -TemplateParameterObject $params
