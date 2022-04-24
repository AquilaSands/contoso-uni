targetScope = 'subscription'

@description('The Azure region of the resource group.')
param location string

@description('The project name. This will form part of the name for the resources.')
param projectName string

@description('The name of the environment e.g., dev, test, prod.')
@allowed([
  'dev'
  'test'
  'prod'
])
param env string

var locationCodes = json(loadTextContent('./location-codes.json'))
var locationCode = locationCodes[location]
var rgName = 'rg-${locationCode}-${env}-${projectName}'

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: rgName
  location: location
}

output name string = rg.name
output location string = rg.location
