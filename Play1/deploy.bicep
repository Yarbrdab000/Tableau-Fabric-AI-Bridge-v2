param location string = resourceGroup().location
param functionAppName string
param keyVaultName string
param kvSecretName string
param tableauPod string
param tableauSite string
param tableauPatName string
param datasourceLuid string

var storageAccountName = 'st${toLower(replace(functionAppName, '-', ''))}'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
}

resource hostingPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${functionAppName}-plan'
  location: location
  sku: { name: 'Y1', tier: 'Dynamic' }
  properties: {}
}

resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
      pythonVersion: '3.12'
      appSettings: [
        { name: 'AzureWebJobsStorage', value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value}' }
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'python' }
        { name: 'KV_URL', value: 'https://${keyVaultName}.vault.azure.net/' }
        { name: 'KV_SECRET_NAME', value: kvSecretName }
        { name: 'TABLEAU_POD', value: tableauPod }
        { name: 'TABLEAU_SITE', value: tableauSite }
        { name: 'TABLEAU_PAT_NAME', value: tableauPatName }
        { name: 'DATASOURCE_LUID', value: datasourceLuid }
      ]
    }
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource kvRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, functionApp.id, 'secrets-user')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output functionAppName string = functionApp.name
output principalId string = functionApp.identity.principalId
output functionUrl string = 'https://${functionApp.properties.defaultHostName}/api/query'
