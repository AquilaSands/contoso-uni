@description('The Azure region of the resource group.')
param location string = resourceGroup().location

@description('The name of the environment e.g., dev, test, prod.')
@allowed([
  'dev'
  'test'
  'prod'
])
param env string

@description('The project name. This will form part of the name for the resources.')
param projectName string

@description('The VNet address prefix e.g., 192.168.0.0/23. Make sure the addresses do not overlap with any VNets that you intend to peer with.')
param vnetAddressPrefix string

@description('The main subnet address range e.g., 192.168.0.0/24. Must be within the VNet address space.')
param mainSubnetIpRange string

@description('The Web App Delegated subnet address prefix e.g., 192.168.1.0/26. Must be within the VNet address space.')
param webAppSubnetIpRange string

@description('The admin user of the SQL Server')
param sqlAdministratorLogin string

@description('The password of the admin user of the SQL Server')
@secure()
param sqlAdministratorLoginPassword string

var nsgRules = json(loadTextContent('./nsg-rules.json'))
var locationCodes = json(loadTextContent('./location-codes.json'))
var locationCode = locationCodes[location]
var baseName = '${locationCode}-${env}-${projectName}-${uniqueString(resourceGroup().id)}'
var nsgName = 'nsg-${baseName}'
var vnetName = 'vnet-${baseName}'
var mainSubnetName = 'snet-main-${baseName}'
var webAppSubnetName = 'snet-webapp-${baseName}'
var kvName = substring('kv-${baseName}', 0, 24)
var logAnalyticsName = 'log-${baseName}'
var appInsightsName = 'appi-${baseName}'
var appPlanName = 'plan-${baseName}'
var appName = 'app-${baseName}'
var sqlServerName = 'sql-${baseName}'
var sqlDatabaseName = 'sqldb-${baseName}'
var isProdEnv = env == 'prod'
var keyVaultSecretsUser = '4633458b-17de-408a-b874-0445c86b69e6'

resource nsg 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: nsgRules
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: vnetName
  location: location
  properties:{
    addressSpace:{
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: mainSubnetName
        properties: {
          addressPrefix: mainSubnetIpRange
          privateEndpointNetworkPolicies: 'Disabled'
          delegations: []
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
      {
        name: webAppSubnetName
        properties: {
          addressPrefix: webAppSubnetIpRange
          privateEndpointNetworkPolicies: 'Enabled'
          delegations: [
            {
              name: 'Microsoft.Web.serverFarms'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2021-11-01-preview' = {
  name: kvName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
    }
    enableRbacAuthorization: true
    // accessPolicies is required for create mode and it needs a static list otherwise it gets clobbered
    // see https://github.com/Azure/azure-resource-manager-schemas/issues/521
    // if the list of accessing identities is not known or needs to be managed separately then use RBAC
    accessPolicies: []
    enabledForTemplateDeployment: false
    enableSoftDelete: true
    enablePurgeProtection: isProdEnv ? true : null // Workaround because this can't be set to false see https://github.com/Azure/bicep/issues/5223
    tenantId: tenant().tenantId
  }

  resource appInsightsInstrumentationKeyKeyVaultSecret 'secrets' = {
    name: 'AppInsightsInstrumentationKey'
    properties: {
      value: applicationInsights.properties.InstrumentationKey
    }
  }

  resource appInsightsConnectionStringKeyVaultSecret 'secrets' = {
    name: 'AppInsightsConnectionString'
    properties: {
      value: applicationInsights.properties.ConnectionString
    }
  }

  resource sqlConnectionStringKeyVaultSecret 'secrets' = {
    name: 'SqlConnectionString'
    properties: {
      value: 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Initial Catalog=${sqlDatabaseName};Persist Security Info=False;User Id=${sqlAdministratorLogin};Password=${sqlAdministratorLoginPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
    }
  }
}

resource keyVaultDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${kvName}'
  scope: keyVault
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'AuditEvent'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: isProdEnv ? 90 : 7
        }
      }
    ]
  }
}

resource keyVaultPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'

  resource keyVaultPrivateDnsZoneLink 'virtualNetworkLinks' = {
    name: 'keyVaultPrivateDnsZoneLink'
    location: 'global'
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnet.id
      }
    }
  }
}

resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2021-05-01' = {
  name: 'pep-${kvName}'
  location: location
  properties: {
    subnet: {
      id: vnet.properties.subnets[0].id
    }
    customDnsConfigs: []
    privateLinkServiceConnections: [
      {
        id : keyVault.id
        name: 'plsc-${kvName}'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }

  resource keyVaultPrivateDnsZoneGroup 'privateDnsZoneGroups' = {
    name: 'keyVaultPrivateDnsZoneGroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: keyVaultPrivateDnsZone.id
          }
        }
      ]
    }
  }
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2021-03-01' = {
  name: appPlanName
  location: location
  sku: {
    name: isProdEnv ? 'P1V3' : 'S1'
    tier: isProdEnv ? 'Premium' : 'Standard'
    capacity:  isProdEnv ? 2 : 1
  }
}

resource webApp 'Microsoft.Web/sites@2021-03-01' = {
  name: appName
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      alwaysOn: true
      netFrameworkVersion: 'v6.0'
      phpVersion: 'off'
      javaVersion: 'off'
      ftpsState: 'Disabled'
      http20Enabled: true
      minTlsVersion: '1.2'
      pythonVersion: 'off'
      use32BitWorkerProcess: true
      nodeVersion: 'off'
      powerShellVersion: 'off'
      vnetName: vnet.name
      vnetRouteAllEnabled: true
      metadata: [
        {
          name: 'CURRENT_STACK'
          value: 'dotnet'
        }
      ]
      appSettings: [
        {
            name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
            value: '@Microsoft.KeyVault(SecretUri=${keyVault::appInsightsInstrumentationKeyKeyVaultSecret.properties.secretUri})'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: '@Microsoft.KeyVault(SecretUri=${keyVault::appInsightsConnectionStringKeyVaultSecret.properties.secretUri})'
        }
        {
          name: 'APPINSIGHTS_PROFILERFEATURE_VERSION'
          value: '1.0.0'
        }
        {
          name: 'APPINSIGHTS_SNAPSHOTFEATURE_VERSION'
          value: '1.0.0'
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~2'
        }
        {
          name: 'InstrumentationEngine_EXTENSION_VERSION'
          value: '~1'
        }
        {
          name: 'SnapshotDebugger_EXTENSION_VERSION'
          value: '~1'
        }
        {
          name: 'DiagnosticServices_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'XDT_MicrosoftApplicationInsights_Mode'
          value: 'recommended'
        }
        {
          name: 'XDT_MicrosoftApplicationInsights_BaseExtensions'
          value: '~1'
        }
        {
          name: 'ConnectionStrings:SchoolContext'
          value: '@Microsoft.KeyVault(SecretUri=${keyVault::sqlConnectionStringKeyVaultSecret.properties.secretUri})'
        }
        {
          name: 'PageSize'
          value: '3'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
    }
    virtualNetworkSubnetId: vnet.properties.subnets[1].id
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource sqlServer 'Microsoft.Sql/servers@2021-11-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: sqlAdministratorLogin
    administratorLoginPassword: sqlAdministratorLoginPassword
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Disabled'
    restrictOutboundNetworkAccess: 'Enabled'
  }

  resource serverAudit 'auditingSettings' = {
    name: 'default'
    properties: {
      state: 'Enabled'
      isAzureMonitorTargetEnabled: true
      isDevopsAuditEnabled: true
      retentionDays: isProdEnv ? 90 : 7
      auditActionsAndGroups: [
          'USER_CHANGE_PASSWORD_GROUP'
          'SUCCESSFUL_DATABASE_AUTHENTICATION_GROUP'
          'FAILED_DATABASE_AUTHENTICATION_GROUP'
      ]
    }
  }

  resource threatDetection 'securityAlertPolicies' = {
    name: 'Default'
    properties: {
      emailAccountAdmins: true
      state: isProdEnv ? 'Enabled' : 'Disabled'
    }
  }
}

// Although it is automatically created we need to define the master db so it can be referenced in diagnostic settings
resource masterDb 'Microsoft.Sql/servers/databases@2021-11-01-preview' = {
  parent: sqlServer
  name: 'master'
  location: location
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2021-11-01-preview' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  sku: {
    name: isProdEnv ? 'S3' : 'S1'
    tier: 'Standard'
  }
}

// Server level diagnostic settings must target the master DB
resource sqlServerDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${sqlServerName}'
  scope: masterDb
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'SQLSecurityAuditEvents'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: isProdEnv ? 90 : 7
        }
      }
    ]
  }
}

resource sqlPrivateDnsZone 'Microsoft.Network/privateDnsZones@2018-09-01' = {
  name: 'privatelink${environment().suffixes.sqlServerHostname}'
  location: 'global'
  dependsOn: [
    vnet
  ]

  resource sqlPrivateDnsZoneLink 'virtualNetworkLinks' = {
    name: 'sqlPrivateDnsZoneLink'
    location: 'global'
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnet.id
      }
    }
  }
}

resource sqlPrivateEndpoint 'Microsoft.Network/privateEndpoints@2020-06-01' = {
  name: 'pep-${sqlServerName}'
  location: location
  properties: {
    subnet: {
      id: vnet.properties.subnets[0].id
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${sqlServerName}'
        properties: {
          privateLinkServiceId: sqlServer.id
          groupIds: [
            'sqlServer'
          ]
        }
      }
    ]
  }

  resource sqlPrivateDnsZoneGroup 'privateDnsZoneGroups' = {
    name: 'sqlPrivateDnsZoneGroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: sqlPrivateDnsZone.id
          }
        }
      ]
    }
  }
}

resource keyVaultAppInsightsConnectionStringRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid(resourceGroup().id, webApp.name ,keyVault.id, keyVault::appInsightsConnectionStringKeyVaultSecret.id)
  scope: keyVault::appInsightsConnectionStringKeyVaultSecret
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUser)
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource keyVaultSqlConnectionStringRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid(resourceGroup().id, webApp.name ,keyVault.id, keyVault::sqlConnectionStringKeyVaultSecret.id)
  scope: keyVault::sqlConnectionStringKeyVaultSecret
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUser)
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output webAppName string = webApp.name
