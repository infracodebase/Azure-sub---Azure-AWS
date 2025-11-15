# Generate random suffix for Storage Account name (must be globally unique)
resource "random_integer" "storage_suffix" {
  min = 100
  max = 999
}

# Storage Account with enhanced security
resource "azurerm_storage_account" "main" {
  name                = "${local.naming.storage_account}${random_integer.storage_suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"

  # Enhanced security settings
  https_traffic_only_enabled       = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  shared_access_key_enabled         = true
  public_network_access_enabled     = false

  # Network rules - restrict access
  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices", "Logging", "Metrics"]

    # Allow access from virtual network subnets
    virtual_network_subnet_ids = [
      azurerm_subnet.private.id
    ]

    # Allow specific IP addresses if provided for management
    ip_rules = var.allowed_ip_addresses
  }

  # Blob properties
  blob_properties {
    versioning_enabled       = true
    change_feed_enabled      = true
    last_access_time_enabled = true

    # Container delete retention policy
    container_delete_retention_policy {
      days = 30
    }

    # Blob delete retention policy
    delete_retention_policy {
      days = 30
    }

    # Blob restore policy
    restore_policy {
      days = 29
    }
  }

  # Queue properties
  queue_properties {
    logging {
      delete                = true
      read                  = true
      write                 = true
      version               = "1.0"
      retention_policy_days = 30
    }

    minute_metrics {
      enabled               = true
      version               = "1.0"
      include_apis          = true
      retention_policy_days = 30
    }

    hour_metrics {
      enabled               = true
      version               = "1.0"
      include_apis          = true
      retention_policy_days = 30
    }
  }

  tags = local.common_tags
}

# Private Endpoint for Storage Account (Blob)
resource "azurerm_private_endpoint" "storage_blob" {
  name                = "pe-${local.naming.storage_account}-blob"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.endpoints.id
  tags                = local.common_tags

  private_service_connection {
    name                           = "psc-${local.naming.storage_account}-blob"
    private_connection_resource_id = azurerm_storage_account.main.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage.id]
  }
}

# Storage containers with secure settings
resource "azurerm_storage_container" "app_data" {
  name                  = "app-data"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "backups" {
  name                  = "backups"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "logs" {
  name                  = "logs"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Storage Account Advanced Threat Protection
resource "azurerm_security_center_storage_defender" "main" {
  storage_account_id = azurerm_storage_account.main.id
}

# Diagnostic Settings for Storage Account
resource "azurerm_monitor_diagnostic_setting" "storage_blob" {
  name                       = "storage-blob-diagnostics"
  target_resource_id         = "${azurerm_storage_account.main.id}/blobServices/default/"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Storage Management Policy for lifecycle management
resource "azurerm_storage_management_policy" "main" {
  storage_account_id = azurerm_storage_account.main.id

  rule {
    name    = "lifecycle-policy"
    enabled = true

    filters {
      prefix_match = ["app-data/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 30
        tier_to_archive_after_days_since_modification_greater_than = 90
        delete_after_days_since_modification_greater_than          = 365
      }

      snapshot {
        delete_after_days_since_creation_greater_than = 90
      }

      version {
        delete_after_days_since_creation = 90
      }
    }
  }
}