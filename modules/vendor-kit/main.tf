# Platform module: everything a vendor app may get in Azure.
# Vendors only set input values; the module decides SKUs, naming and security.

# --- Context: the vendor's resource group and the identity running Terraform -------
data "azurerm_resource_group" "vendor" {
  name = var.resource_group_name
}

data "azurerm_client_config" "current" {}

# --- Storage account ------------------------------------------------------------------
# SHORTCUT: public endpoint and shared keys stay enabled (no private endpoint in the demo).
resource "azurerm_storage_account" "this" {
  name                            = var.storage_account_name
  resource_group_name             = data.azurerm_resource_group.vendor.name
  location                        = data.azurerm_resource_group.vendor.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                            = { vendor = var.vendor, app = var.app }
}

# --- Blob containers the vendor listed (created through ARM, no data-plane rights needed) ---
resource "azurerm_storage_container" "this" {
  for_each              = toset(var.containers)
  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# --- The app's own identity may read blobs: no connection string in the app ----------
resource "azurerm_role_assignment" "app_blob_reader" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = var.app_identity_principal_id
  principal_type       = "ServicePrincipal"
}

# --- Optional Azure SQL: serverless, pauses after 1 h idle, Entra-only login ----------
resource "azurerm_mssql_server" "this" {
  count               = var.enable_sql ? 1 : 0
  name                = "sql-${var.storage_account_name}"
  resource_group_name = data.azurerm_resource_group.vendor.name
  location            = data.azurerm_resource_group.vendor.location
  version             = "12.0"
  minimum_tls_version = "1.2"

  azuread_administrator {
    login_username              = "platform-github"
    object_id                   = data.azurerm_client_config.current.object_id
    azuread_authentication_only = true
  }
}

resource "azurerm_mssql_database" "this" {
  count                       = var.enable_sql ? 1 : 0
  name                        = var.app
  server_id                   = azurerm_mssql_server.this[0].id
  sku_name                    = "GP_S_Gen5_1"
  min_capacity                = 0.5
  auto_pause_delay_in_minutes = 60
  max_size_gb                 = 2
}
