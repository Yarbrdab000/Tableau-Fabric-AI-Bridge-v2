#!/usr/bin/env pwsh

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Tableau + Fabric AI Bridge - Play 1  " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ── Azure login check ─────────────────────────────────────────────────────────
Write-Host "Checking Azure authentication..." -ForegroundColor Yellow
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "Not logged in. Starting device code login..." -ForegroundColor Yellow
    Write-Host "(This supports SSO and MFA — complete the login in your browser)" -ForegroundColor Gray
    az login --use-device-code
    $account = az account show | ConvertFrom-Json
}
Write-Host "Logged in as: $($account.user.name)" -ForegroundColor Green

# ── Collect inputs ────────────────────────────────────────────────────────────
$subscriptionId  = Read-Host "Azure Subscription ID"
$resourceGroup   = Read-Host "Resource Group name"
$functionAppName = Read-Host "Function App name (new, globally unique)"
$keyVaultName    = Read-Host "Key Vault name (existing)"
$kvSecretName    = Read-Host "Key Vault secret name (existing secret storing your Tableau PAT)"
$tableauPod      = Read-Host "Tableau pod (e.g. 10ay.online.tableau.com)"
$tableauSite     = Read-Host "Tableau site content URL slug"
$tableauPatName  = Read-Host "Tableau PAT name"
$datasourceName  = Read-Host "Tableau datasource name"

Write-Host ""
Write-Host "Setting subscription..." -ForegroundColor Yellow
az account set --subscription $subscriptionId

# ── Resolve datasource LUID ───────────────────────────────────────────────────
Write-Host ""
Write-Host "Resolving datasource LUID..." -ForegroundColor Yellow

$patPlain = az keyvault secret show --vault-name $keyVaultName --name $kvSecretName --query "value" -o tsv

$signinBody = @{
    credentials = @{
        personalAccessTokenName   = $tableauPatName
        personalAccessTokenSecret = $patPlain
        site                      = @{ contentUrl = $tableauSite }
    }
} | ConvertTo-Json -Depth 5

$signinResp = Invoke-RestMethod `
    -Uri "https://$tableauPod/api/3.24/auth/signin" `
    -Method POST `
    -ContentType "application/json" `
    -Headers @{ "Accept" = "application/json" } `
    -Body $signinBody

$token  = $signinResp.credentials.token
$siteId = $signinResp.credentials.site.id

$dsResp = Invoke-RestMethod `
    -Uri "https://$tableauPod/api/3.24/sites/$siteId/datasources?pageSize=1000" `
    -Method GET `
    -Headers @{ "X-Tableau-Auth" = $token; "Accept" = "application/json" }

$matches = $dsResp.datasources.datasource | Where-Object { $_.name -eq $datasourceName }

if ($matches.Count -eq 0) {
    Write-Host "ERROR: No datasource found with name '$datasourceName'" -ForegroundColor Red
    exit 1
} elseif ($matches.Count -eq 1) {
    $datasourceLuid = $matches[0].id
    Write-Host "Datasource found: $datasourceName ($datasourceLuid)" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "Multiple datasources found with name '$datasourceName':" -ForegroundColor Yellow
    $i = 1
    foreach ($ds in $matches) {
        Write-Host "  [$i] $($ds.name) — Project: $($ds.project.name) — LUID: $($ds.id)"
        $i++
    }
    $selection = Read-Host "Enter number to select"
    $datasourceLuid = $matches[$selection - 1].id
    Write-Host "Selected: $($matches[$selection - 1].name) ($datasourceLuid)" -ForegroundColor Green
}

# ── Deploy Bicep ──────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Deploying Function App infrastructure..." -ForegroundColor Yellow

az deployment group create `
    --resource-group $resourceGroup `
    --template-file "$PSScriptRoot/deploy.bicep" `
    --parameters `
        functionAppName=$functionAppName `
        keyVaultName=$keyVaultName `
        kvSecretName=$kvSecretName `
        tableauPod=$tableauPod `
        tableauSite=$tableauSite `
        tableauPatName=$tableauPatName `
        datasourceLuid=$datasourceLuid `
    --output table

Write-Host "Infrastructure deployed." -ForegroundColor Green

# ── Enable remote build ───────────────────────────────────────────────────────
Write-Host ""
Write-Host "Enabling remote build..." -ForegroundColor Yellow
az functionapp config appsettings set `
    --name $functionAppName `
    --resource-group $resourceGroup `
    --settings "SCM_DO_BUILD_DURING_DEPLOYMENT=true" | Out-Null

# ── Package and deploy Function code ─────────────────────────────────────────
Write-Host ""
Write-Host "Packaging Function code..." -ForegroundColor Yellow

$funcDir = "$PSScriptRoot/function_app"
$zipPath = "$PSScriptRoot/function_app_deploy.zip"

if (Test-Path $zipPath) { Remove-Item $zipPath }

Push-Location $funcDir
zip -r $zipPath . | Out-Null
Pop-Location

Write-Host "Deploying Function code (remote build)..." -ForegroundColor Yellow
az functionapp deployment source config-zip `
    --resource-group $resourceGroup `
    --name $functionAppName `
    --src $zipPath `
    --build-remote true

Write-Host "Function code deployed." -ForegroundColor Green

# ── Wait for function to initialize ──────────────────────────────────────────
Write-Host ""
Write-Host "Waiting for Function App to initialize (60 seconds)..." -ForegroundColor Yellow
Start-Sleep -Seconds 60

# ── Get function URL ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Retrieving Function URL..." -ForegroundColor Yellow

$funcKey = az functionapp keys list `
    --resource-group $resourceGroup `
    --name $functionAppName `
    --query "functionKeys.default" -o tsv

$functionUrl = "https://$functionAppName.azurewebsites.net/api/query?code=$funcKey"

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Function URL:" -ForegroundColor Cyan
Write-Host $functionUrl
Write-Host ""
Write-Host "Datasource LUID: $datasourceLuid" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next: paste the Function URL into your Foundry agent OpenAPI spec." -ForegroundColor Yellow
Write-Host ""
