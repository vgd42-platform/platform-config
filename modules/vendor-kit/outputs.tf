output "blob_endpoint" {
  value = azurerm_storage_account.this.primary_blob_endpoint
}

output "sql_server_fqdn" {
  value = var.enable_sql ? azurerm_mssql_server.this[0].fully_qualified_domain_name : null
}
