# Get current client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for Key Vault name (must be globally unique)
resource "random_integer" "key_vault_suffix" {
  min = 100
  max = 999
}

# Key Vault with enhanced security
resource "azurerm_key_vault" "main" {
  name                = "${local.naming.key_vault}${random_integer.key_vault_suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.key_vault_sku

  # Enhanced security settings
  enabled_for_deployment         = false
  enabled_for_disk_encryption     = true
  enabled_for_template_deployment = false
  enable_rbac_authorization       = true
  purge_protection_enabled        = true
  soft_delete_retention_days      = 7

  # Network access restrictions
  public_network_access_enabled = false

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"

    # Allow access from virtual network subnets
    virtual_network_subnet_ids = [
      azurerm_subnet.private.id
    ]

    # Allow specific IP addresses if provided
    ip_rules = var.allowed_ip_addresses
  }

  tags = local.common_tags
}

# Private Endpoint for Key Vault
resource "azurerm_private_endpoint" "key_vault" {
  name                = "pe-${local.naming.key_vault}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.endpoints.id
  tags                = local.common_tags

  private_service_connection {
    name                           = "psc-${local.naming.key_vault}"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.key_vault.id]
  }
}

# Key Vault Access Policy for current service principal (for Terraform management)
resource "azurerm_role_assignment" "key_vault_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Key Vault Access Policy for applications (example)
resource "azurerm_role_assignment" "key_vault_secrets_user" {
  count                = length(var.allowed_ip_addresses) > 0 ? 1 : 0
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Generate PostgreSQL admin password and store in Key Vault
resource "random_password" "postgresql_admin_password" {
  length  = 32
  special = true
}

resource "azurerm_key_vault_secret" "postgresql_admin_password" {
  name         = "postgresql-admin-password"
  value        = random_password.postgresql_admin_password.result
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags

  depends_on = [
    azurerm_role_assignment.key_vault_admin
  ]
}

# Storage Account access key (will be stored after storage account creation)
resource "azurerm_key_vault_secret" "storage_account_key" {
  name         = "storage-account-key"
  value        = azurerm_storage_account.main.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags

  depends_on = [
    azurerm_role_assignment.key_vault_admin,
    azurerm_storage_account.main
  ]
}