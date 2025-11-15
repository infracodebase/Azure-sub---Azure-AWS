variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US 2"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "secure-infra"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "allowed_ip_addresses" {
  description = "List of allowed IP addresses for development access"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Environment   = "dev"
    Project       = "secure-infrastructure"
    ManagedBy     = "terraform"
    SecurityLevel = "high"
  }
}

# Database configuration
variable "postgresql_admin_username" {
  description = "PostgreSQL administrator username"
  type        = string
  default     = "psqladmin"
  sensitive   = true
}

variable "postgresql_sku_name" {
  description = "PostgreSQL SKU name"
  type        = string
  default     = "GP_Standard_D2s_v3"
}

variable "postgresql_storage_mb" {
  description = "PostgreSQL storage in MB"
  type        = number
  default     = 32768
}

# Key Vault configuration
variable "key_vault_sku" {
  description = "Key Vault SKU"
  type        = string
  default     = "standard"
}

# Storage Account configuration
variable "storage_account_tier" {
  description = "Storage Account tier"
  type        = string
  default     = "Standard"
}

variable "storage_replication_type" {
  description = "Storage Account replication type"
  type        = string
  default     = "LRS"
}