# --- Set by onboarding (identity of the vendor app) ---------------------------------
variable "vendor" { type = string }
variable "app" { type = string }
variable "resource_group_name" { type = string }  # created by onboarding
variable "storage_account_name" { type = string } # globally unique, chosen by onboarding
variable "app_identity_principal_id" { type = string }

# --- Values the vendor may change (through a PR to its deploy repo) ------------------
variable "containers" {
  description = "Blob containers the app needs"
  type        = list(string)
  default     = []
}

variable "enable_sql" {
  description = "Create a small serverless Azure SQL database (pauses when idle)"
  type        = bool
  default     = false
}
