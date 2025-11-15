locals {
  # Generate consistent resource names
  resource_prefix = "${var.project_name}-${var.environment}"

  # Region abbreviation for naming
  region_short = {
    "us-east-1"      = "use1"
    "us-east-2"      = "use2"
    "us-west-1"      = "usw1"
    "us-west-2"      = "usw2"
    "eu-west-1"      = "euw1"
    "eu-west-2"      = "euw2"
    "eu-central-1"   = "euc1"
    "ap-southeast-1" = "apse1"
    "ap-southeast-2" = "apse2"
  }

  region_abbr = lookup(local.region_short, var.region, "unk")

  # Common naming convention
  naming = {
    vpc                    = "${local.region_abbr}-${local.resource_prefix}-vpc"
    private_subnet_prefix  = "${local.region_abbr}-${local.resource_prefix}-private"
    database_subnet_prefix = "${local.region_abbr}-${local.resource_prefix}-database"
    security_group_prefix  = "${local.region_abbr}-${local.resource_prefix}"
    kms_key               = "${local.region_abbr}-${local.resource_prefix}-key"
    secrets_manager       = "${local.region_abbr}/${local.resource_prefix}"
    s3_bucket_prefix      = "${local.region_abbr}-${replace(local.resource_prefix, "-", "")}"
    rds_instance          = "${local.region_abbr}-${local.resource_prefix}-postgres"
    cloudwatch_prefix     = "${local.region_abbr}-${local.resource_prefix}"
  }

  # Merge tags with environment-specific tags
  common_tags = merge(var.tags, {
    Environment = var.environment
    Region      = var.region
    CreatedBy   = "terraform"
    CreatedDate = formatdate("YYYY-MM-DD", timestamp())
  })

  # Get availability zones dynamically
  azs = slice(data.aws_availability_zones.available.names, 0, var.availability_zones)

  # Network configuration
  private_subnets = [
    for i, az in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 1)
  ]

  database_subnets = [
    for i, az in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 10)
  ]
}

# Data sources
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}