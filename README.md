# Contoso University Infrastructure as Code Deployment to Azure

## About

This project uses an Azure DevOps pipeline to deploy the demo app from [Razor Pages with Entity Framework Core in ASP.NET Core](https://docs.microsoft.com/en-us/aspnet/core/data/ef-rp/intro?view=aspnetcore-6.0&tabs=visual-studio-code) to Azure.

The infrastructure is defined using [Bicep](https://github.com/Azure/bicep) and is deployed using PowerShell as part of the pipeline. The pipeline will lint the Bicep files and test them using [PSRule](https://github.com/microsoft/PSRule) before validating the deployment and then performing a 'what if' analysis before the actual deployment. This allows for an approval step to be configured in Azure Devops so that if required a manual review of the changes can be done before the actual deployment.

The following infrastructure is used:

- App Service Plan and Web App
- Key Vault
- Azure SQL DB
- Application Insights
- Log Analytics Workspace
- VNet
- Private Endpoints for Azure SQL DB and KeyVault

Key Vault and the Azure SQL DB have public network access disabled with access restricted to VNet traffic and have been configured for auditing with logs sent to the Log Analytics workspace.

Application Insights is also integrated with the Log Analytics workspace to provide centralised monitoring and observability for the solution.

The web app is configured with a managed service identity and this identity has RBAC permissions to read the secrets stored in Key Vault.

## Azure DevOps Setup

Azure DevOps is used to run the CI/CD pipeline. The pipeline definition is in the .azure-pipelines folder and is built using templates to support repeatable deployments to multiple environments (although only a dev environment has been configured).

To run this pipeline you will need to configure the following in Azure DevOps:

- Install the PSRule extension from the marketplace <https://marketplace.visualstudio.com/items?itemName=bewhite.ps-rule>

- An Azure Resource Manager Service Connection with the necessary permisions to create resource groups and services.

- An Environment. By default the pipeline uses `dev` so this should be the name of the environment. If you want a different name you will need to update the pipeline parameter in `azure-pipelines.yml`.

- A Variable Group called `contoso-uni-shared`. Add a variable called `serviceConnectionName` and set the value to the name of the Azure Resource Manager Service Connection used for deployments.

- A Variable Group for the environment called `contoso-uni-{ENV}`. Replace the `{ENV}` placeholder with the name of the environment it should be associated with. If using the default dev environment the name should be `contoso-uni-dev`. The variables in the group should match the parameters of the `main.bicep` file (see the file for their descriptions).  
Variables:
  - location
  - mainSubnetIpRange
  - projectName
  - sqlAdministratorLogin
  - sqlAdministratorLoginPassword (make this one a secret)
  - vnetAddressPrefix
  - webAppSubnetIpRange

The pipeline will need to be given permissions to access the variable groups, service connection and environment. This can be done during the first run or prior to running the pipeline.
