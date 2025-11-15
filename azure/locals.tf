locals {
  # Generate consistent resource names
  resource_prefix = "${var.project_name}-${var.environment}"

  # Location abbreviation for naming
  location_short = {
    "East US"      = "eus"
    "East US 2"    = "eus2"
    "West US"      = "wus"
    "West US 2"    = "wus2"
    "Central US"   = "cus"
    "North Europe" = "neu"
    "West Europe"  = "weu"
  }

  location_abbr = lookup(local.location_short, var.location, "unk")

  # Common naming convention
  naming = {
    resource_group     = "rg-${local.location_abbr}-${local.resource_prefix}"
    virtual_network    = "vnet-${local.location_abbr}-${local.resource_prefix}"
    subnet_private     = "snet-${local.location_abbr}-${local.resource_prefix}-private"
    subnet_endpoints   = "snet-${local.location_abbr}-${local.resource_prefix}-endpoints"
    nsg_private        = "nsg-${local.location_abbr}-${local.resource_prefix}-private"
    nsg_endpoints      = "nsg-${local.location_abbr}-${local.resource_prefix}-endpoints"
    key_vault          = "kv-${local.location_abbr}-${replace(local.resource_prefix, "-", "")}"
    storage_account    = "st${local.location_abbr}${replace(local.resource_prefix, "-", "")}"
    postgresql         = "psql-${local.location_abbr}-${local.resource_prefix}"
    log_analytics      = "law-${local.location_abbr}-${local.resource_prefix}"
    app_insights       = "appi-${local.location_abbr}-${local.resource_prefix}"
  }

  # Merge tags with environment-specific tags
  common_tags = merge(var.tags, {
    Environment = var.environment
    Location    = var.location
    CreatedBy   = "terraform"
    CreatedDate = formatdate("YYYY-MM-DD", timestamp())
  })

  # Network configuration
  vnet_address_space     = ["10.0.0.0/16"]
  private_subnet_prefix  = "10.0.1.0/24"
  endpoint_subnet_prefix = "10.0.2.0/24"
}