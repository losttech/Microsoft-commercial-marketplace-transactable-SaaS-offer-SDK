﻿#
# Powershell script to deploy the resources - Customer portal, Publisher portal and the Azure SQL Database
#

Param(  
   [Parameter(Mandatory=$true)]
   [string]$WebAppNamePrefix, # Prefix used for creating web applications
   [Parameter(Mandatory=$true)]
   [string]$TenantID, # The value should match the value provided for Active Directory TenantID in the Technical Configuration of the Transactable Offer in Partner Center
   [Parameter(Mandatory=$true)]
   [string]$ADApplicationID, # The value should match the value provided for Active Directory Application ID in the Technical Configuration of the Transactable Offer in Partner Center
   [Parameter(Mandatory=$true)]
   [string]$ADApplicationSecret, # Secret key of the AD Application
   [Parameter(Mandatory=$true)]
   [string]$SQLServerName, # Name of the database server (without database.windows.net)
   [Parameter(Mandatory=$true)]
   [string]$SQLAdminLogin, # SQL Admin login
   [Parameter(Mandatory=$true)]
   [string]$SQLAdminLoginPassword, # SQL Admin password
   [Parameter(Mandatory=$true)]
   [string]$PublisherAdminUsers, # Provide a list of email addresses (as comma-separated-values) that should be granted access to the Publisher Portal
   [Parameter(Mandatory=$true)]
   [string]$BacpacResourceGroup, # Name of the resource group to get bacpac from
   [Parameter(Mandatory=$true)]
   [string]$BacpacStorageAccount, # Name of the storage account to get bacpac from
   [Parameter(Mandatory=$true)]
   [string]$BacpacStorageContainer, # Name of the storage container to get bacpac from
   [Parameter(Mandatory=$true)]
   [string]$ResourceGroupForDeployment, # Name of the resource group to deploy the resources
   [Parameter(Mandatory=$true)]
   [string]$Location, # Location of the resource group
   [Parameter(Mandatory=$true)]
   [string]$AzureSubscriptionID, # Subscription where the resources be deployed

   [Parameter(Mandatory=$true)]
   [string]$PublisherPortalZip, # Path to the zip file containing publisher portal
   [Parameter(Mandatory=$true)]
   [string]$CustomerPortalZip, # Path to the zip file containing customer portal

   [Parameter(Mandatory=$true)]
   [string]$PathToARMTemplate              # Local Path to the ARM Template
)

#   Make sure to install Az Module before running this script
#   Install-Module Az

if (!(Test-Path $PublisherPortalZip -PathType Leaf)){
    throw ("Missing file: " + $PublisherPortalZip)
}

if (!(Test-Path $CustomerPortalZip -PathType Leaf)){
    throw ("Missing file: " + $CustomerPortalZip)
}

$TempFolderToStoreBacpac = Join-Path $env:TEMP 'AMPSaaSDatabase'
$BacpacFileName = "AMPSaaSDB.bacpac"
$LocalPathToBacpacFile = Join-Path $TempFolderToStoreBacpac $BacpacFileName  

# Create a temporary folder
New-Item -Path $TempFolderToStoreBacpac -ItemType Directory -Force

$distStorageAccount = Get-AzStorageAccount -ResourceGroupName $BacpacResourceGroup -Name $BacpacStorageAccount
Get-AzStorageBlobContent -Context $distStorageAccount.Context -Container $BacpacStorageContainer -Blob $BacpacFileName -Destination $TempFolderToStoreBacpac

$storagepostfix = Get-Random -Minimum 1 -Maximum 1000

$StorageAccountName = "amptmpstorage" + $storagepostfix       #enter storage account name

$ContainerName = "packagefiles" #container name for uploading SQL DB file 
$resourceGroupForStorageAccount = "amptmpstorage"   #resource group name for the storage account.
                                                      

Write-host "Select subscription : $AzureSubscriptionID" 
Select-AzSubscription -SubscriptionId $AzureSubscriptionID


Write-host "Creating a temporary resource group and storage account - $resourceGroupForStorageAccount"
New-AzResourceGroup -Name $resourceGroupForStorageAccount -Location $location -Force
try{
New-AzStorageAccount -ResourceGroupName $resourceGroupForStorageAccount -Name $StorageAccountName -Location $location -SkuName Standard_LRS -Kind StorageV2
$StorageAccountKey = @((Get-AzStorageAccountKey -ResourceGroupName $resourceGroupForStorageAccount -Name $StorageAccountName).Value)
$key = $StorageAccountKey[0]

$ctx = New-AzstorageContext -StorageAccountName $StorageAccountName  -StorageAccountKey $key

New-AzStorageContainer -Name $ContainerName -Context $ctx -Permission Blob 
Set-AzStorageBlobContent -File $LocalPathToBacpacFile -Container $ContainerName -Blob $BlobName -Context $ctx -Force

$URLToBacpacFromStorage = (Get-AzStorageBlob -blob $BlobName -Container $ContainerName -Context $ctx).ICloudBlob.uri.AbsoluteUri

Write-host "Uploaded the bacpac file to $URLToBacpacFromStorage"    

Write-host "Upload published files to storage account"
Set-AzStorageBlobContent -File $PublisherPortalZip -Container $ContainerName -Blob "PublisherPortal.zip" -Context $ctx -Force
Set-AzStorageBlobContent -File $CustomerPortalZip -Container $ContainerName -Blob "CustomerPortal.zip" -Context $ctx -Force

# The base URI where artifacts required by this template are located
$PathToWebApplicationPackages = ((Get-AzStorageContainer -Container $ContainerName -Context $ctx).CloudBlobContainer.uri.AbsoluteUri)

Write-host "Path to web application packages $PathToWebApplicationPackages"

#Parameter for ARM template, Make sure to add values for parameters before running the script.
$ARMTemplateParams = @{
   webAppNamePrefix             = "$WebAppNamePrefix"
   TenantID                     = "$TenantID"
   ADApplicationID              = "$ADApplicationID"
   ADApplicationSecret          = "$ADApplicationSecret"
   SQLServerName                = "$SQLServerName"
   SQLAdminLogin                = "$SQLAdminLogin"
   SQLAdminLoginPassword        = "$SQLAdminLoginPassword"
   bacpacUrl                    = "$URLToBacpacFromStorage"
   SAASKeyForbacpac             = ""
   PublisherAdminUsers          = "$PublisherAdminUsers"
   PathToWebApplicationPackages = "$PathToWebApplicationPackages"
}


# Create RG if not exists
# New-AzResourceGroup -Name $ResourceGroupForDeployment -Location $location -Force

Write-host "Deploying the ARM template to set up resources"
# Deploy resources using ARM template
New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupForDeployment -TemplateFile $PathToARMTemplate -TemplateParameterObject $ARMTemplateParams

} finally {
Write-host "Cleaning things up!"
# Cleanup : Delete the temporary storage account and the resource group created to host the bacpac file.
Remove-AzResourceGroup -Name $resourceGroupForStorageAccount -Force 
Remove-Item –path $TempFolderToStoreBacpac –recurse
}
Write-host "Done!"