param($ResourceGroupName, $ParamsHashTable)
# Params:
# location, env, projectName, vnetAddressPrefix, mainSubnetIpRange,
# webAppSubnetIpRange, sqlAdministratorLogin, sqlAdministratorLoginPassword

Test-AzResourceGroupDeployment `
    -ResourceGroupName $ResourceGroupName `
    -TemplateFile main.bicep `
    -TemplateParameterObject $ParamsHashTable `
    -SkipTemplateParameterPrompt
