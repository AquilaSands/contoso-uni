param($ResourceGroupName, $ParamsHashTable)
# Params:
# location, env, projectName, vnetAddressPrefix, mainSubnetIpRange,
# webAppSubnetIpRange, sqlAdministratorLogin, sqlAdministratorLoginPassword

New-AzResourceGroupDeployment `
    -ResourceGroupName $ResourceGroupName `
    -TemplateFile main.bicep `
    -TemplateParameterObject $ParamsHashTable `
    -SkipTemplateParameterPrompt
