# Azure resources of __APP__ (vendor __VENDOR__).
# The vendor changes only the two values marked below, by PR. The platform module
# decides everything else (SKUs, security, naming).

# --- State lives in the platform's storage account (set by the infra workflow) ---
terraform {
  backend "azurerm" {}
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  resource_provider_registrations = "none" # registered once at bootstrap
}

# --- The platform module ---
module "vendor_kit" {
  source = "github.com/__ORG__/platform-config//modules/vendor-kit?ref=main"

  # Set at onboarding - don't change
  vendor                    = "__VENDOR__"
  app                       = "__APP__"
  resource_group_name       = "rg-__PREFIX__-__VENDOR__-__APP__"
  storage_account_name      = "__STORAGE__"
  app_identity_principal_id = "__APP_PRINCIPAL_ID__"

  # Vendor may change (PR, a code owner approves)
  containers = ["orders"]
  enable_sql = false
}

output "blob_endpoint" {
  value = module.vendor_kit.blob_endpoint
}
