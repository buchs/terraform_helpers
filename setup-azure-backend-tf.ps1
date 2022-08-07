# Setup for running Terraform for Azure Backend storage

# distribution: all who will be running Terraform

# reference: https://docs.microsoft.com/en-us/azure/developer/
#            terraform/store-state-in-azure-storage

# running as "./setup-for-tf.ps1 destroy" will destroy what you have
# created previously. Be careful!
# If you are not logged in via Azure CLI, this script will fail!

# Original: Kevin Buchs (kevin.buchs@gmail.com) 2022-08-06

param (
   [string]$destroy = ''
)

# customize these:
$REGION = 'eastus'
$STORAGE_ACCOUNT = '000012341071simpaytf'
$RESOURCE_GROUP = 'terraform_admin'
$CONTAINER_NAME = 'tfstate'


if ($destroy -ne 'destroy') { $destroy = ''; }

# take inventory
$rg_exists = az group list --query '[].name' | select-string -quiet  `
   -pattern $RESOURCE_GROUP
if ($rg_exists -ne $True) { 
   $rg_exists = $False
   $sa_exists = $False
   $sc_exists = $False
}
else {
   $sa_exists = az storage account list --query '[].name' | select-string  `
      -pattern $STORAGE_ACCOUNT -quiet
   if ($sa_exists) {
      # This is duplicated below, but I need it here
      # and this is nested in ifs and it might not work otherwise
      $account_key = az storage account keys list  `
         --resource-group $RESOURCE_GROUP  `
         --account-name $STORAGE_ACCOUNT  `
         --query '[0].value' -o tsv
      $sc_exists = az storage container list  `
         --account-name $STORAGE_ACCOUNT  `
         --account-key $account_key |  `
         select-string $CONTAINER_NAME -quiet   
   }
   else {
      $sc_exists = $False
   }
}

if ($destroy -eq '') {
   # create what is needed and get access key
   if (! $rg_exists) {
      write-output 'creating resource group'
      az group create --name $RESOURCE_GROUP --location $REGION |  `
         select-string 'provisioningState' -quiet
   }
   if (! $sa_exists) {
      write-output 'creating storage account'
      az storage account create --resource-group $RESOURCE_GROUP  `
         --name $STORAGE_ACCOUNT --sku Standard_LRS  `
         --encryption-services blob |  `
         select-string 'statusOfPrimary' -quiet
   }

   # set an environment variable to hold the storage account 
   # access key for Terraform to use
   # This just picks the first key and does not examine
   # the permissions. One could alternatively give
   # the name of the key.  
   $env:ARM_ACCESS_KEY = az storage account keys list  `
      --resource-group $RESOURCE_GROUP  `
      --account-name $STORAGE_ACCOUNT  `
      --query '[0].value' -o tsv

   if (! $sc_exists) {
      write-output 'creating storage container'
      az storage container create --name $CONTAINER_NAME  `
         --account-name $STORAGE_ACCOUNT  `
         --account-key $env:ARM_ACCESS_KEY | select-string 'created' -quiet
   }


} else {
   # destroy what exists
   if ($sc_exists) {
      write-output 'destroying storage container'
      $account_key = az storage account keys list  `
         --resource-group $RESOURCE_GROUP  `
         --account-name $STORAGE_ACCOUNT  `
         --query '[0].value' -o tsv
	
      az storage container delete --name $CONTAINER_NAME  `
         --account-name $STORAGE_ACCOUNT  `
         --account-key $account_key | select-string 'deleted' -quiet
   }
   if ($sa_exists) {
      write-output 'destroying storage account'
      az storage account delete --resource-group $RESOURCE_GROUP  `
         --name $STORAGE_ACCOUNT -y
   }
   if ($rg_exists) {
      write-output 'destroying resource group'
      az group delete --name $RESOURCE_GROUP -y
   }
}
