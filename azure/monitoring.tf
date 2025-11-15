# Log Analytics Workspace for centralized logging
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.naming.log_analytics
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.environment == "prod" ? 90 : 30
  tags                = local.common_tags
}

# Application Insights for application monitoring
resource "azurerm_application_insights" "main" {
  name                = local.naming.app_insights
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = local.common_tags
}

# Security Center - Enable Advanced Threat Protection
data "azurerm_subscription" "current" {}

# Enable Security Center for the subscription (requires appropriate permissions)
resource "azurerm_security_center_subscription_pricing" "main" {
  count         = var.environment == "prod" ? 1 : 0
  tier          = "Standard"
  resource_type = "VirtualMachines"
}

# Action Groups for alerts
resource "azurerm_monitor_action_group" "security_alerts" {
  name                = "security-alerts-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "secalerts"
  tags                = local.common_tags

  # Add email notifications - customize as needed
  email_receiver {
    name                    = "security-team"
    email_address           = "security@yourdomain.com"
    use_common_alert_schema = true
  }

  # Add webhook notifications - customize as needed
  webhook_receiver {
    name                    = "security-webhook"
    service_uri             = "https://your-webhook-url.com/security"
    use_common_alert_schema = true
  }
}

# Action Group for operational alerts
resource "azurerm_monitor_action_group" "operational_alerts" {
  name                = "operational-alerts-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "opalerts"
  tags                = local.common_tags

  email_receiver {
    name                    = "ops-team"
    email_address           = "ops@yourdomain.com"
    use_common_alert_schema = true
  }
}

# Security Alerts - Failed login attempts to Key Vault
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "key_vault_access_failures" {
  name                = "key-vault-access-failures"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"
  scopes               = [azurerm_log_analytics_workspace.main.id]
  severity             = 2

  criteria {
    query                   = <<-QUERY
      AzureDiagnostics
      | where ResourceProvider == "MICROSOFT.KEYVAULT"
      | where ResultSignature == "Forbidden"
      | summarize count() by bin(TimeGenerated, 5m)
      | where count_ > 5
    QUERY
    time_aggregation_method = "Count"
    threshold               = 5
    operator                = "GreaterThan"

    dimension {
      name     = "ResourceId"
      operator = "Include"
      values   = ["*"]
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.security_alerts.id]
  }

  tags = local.common_tags
}

# Operational Alerts - PostgreSQL Connection Issues
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "postgresql_connection_failures" {
  name                = "postgresql-connection-failures"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  evaluation_frequency = "PT5M"
  window_duration      = "PT15M"
  scopes               = [azurerm_log_analytics_workspace.main.id]
  severity             = 3

  criteria {
    query                   = <<-QUERY
      AzureDiagnostics
      | where ResourceProvider == "MICROSOFT.DBFORPOSTGRESQL"
      | where Category == "PostgreSQLLogs"
      | where Message contains "connection"
      | where Message contains "failed"
      | summarize count() by bin(TimeGenerated, 15m)
      | where count_ > 10
    QUERY
    time_aggregation_method = "Count"
    threshold               = 10
    operator                = "GreaterThan"
  }

  action {
    action_groups = [azurerm_monitor_action_group.operational_alerts.id]
  }

  tags = local.common_tags
}

# Storage Account Alert - Unusual Access Patterns
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "storage_unusual_access" {
  name                = "storage-unusual-access"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  evaluation_frequency = "PT15M"
  window_duration      = "PT1H"
  scopes               = [azurerm_log_analytics_workspace.main.id]
  severity             = 2

  criteria {
    query                   = <<-QUERY
      StorageBlobLogs
      | where StatusCode >= 400
      | summarize count() by bin(TimeGenerated, 1h), CallerIpAddress
      | where count_ > 50
    QUERY
    time_aggregation_method = "Count"
    threshold               = 50
    operator                = "GreaterThan"
  }

  action {
    action_groups = [azurerm_monitor_action_group.security_alerts.id]
  }

  tags = local.common_tags
}

# Metric Alerts - High CPU on PostgreSQL
resource "azurerm_monitor_metric_alert" "postgresql_high_cpu" {
  name                = "postgresql-high-cpu"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_postgresql_flexible_server.main.id]
  description         = "PostgreSQL server is experiencing high CPU usage"
  severity            = 2

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  frequency   = "PT1M"
  window_size = "PT5M"

  action {
    action_group_id = azurerm_monitor_action_group.operational_alerts.id
  }

  tags = local.common_tags
}

# Metric Alert - Storage Account High Transaction Count
resource "azurerm_monitor_metric_alert" "storage_high_transactions" {
  name                = "storage-high-transactions"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_storage_account.main.id]
  description         = "Storage account is experiencing high transaction volume"
  severity            = 3

  criteria {
    metric_namespace = "Microsoft.Storage/storageAccounts"
    metric_name      = "Transactions"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10000
  }

  frequency   = "PT5M"
  window_size = "PT15M"

  action {
    action_group_id = azurerm_monitor_action_group.operational_alerts.id
  }

  tags = local.common_tags
}

# Workbook for Security Dashboard (optional)
resource "azurerm_application_insights_workbook" "security_dashboard" {
  name                = "security-dashboard-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  display_name        = "Security Dashboard - ${var.environment}"

  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [{
      type = 1
      content = {
        json = "# Security Dashboard\nMonitoring security events across Key Vault, PostgreSQL, and Storage Account."
      }
    }]
  })

  tags = local.common_tags
}