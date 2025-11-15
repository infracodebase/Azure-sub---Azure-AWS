variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-2"
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
  description = "List of allowed IP addresses for development access (CIDR format)"
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
  default     = "postgres"
  sensitive   = true
}

variable "postgresql_instance_class" {
  description = "PostgreSQL instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "postgresql_allocated_storage" {
  description = "PostgreSQL allocated storage in GB"
  type        = number
  default     = 20
}

variable "postgresql_max_allocated_storage" {
  description = "PostgreSQL maximum allocated storage in GB"
  type        = number
  default     = 100
}

# S3 configuration
variable "s3_versioning" {
  description = "Enable S3 versioning"
  type        = bool
  default     = true
}

variable "s3_lifecycle_enabled" {
  description = "Enable S3 lifecycle management"
  type        = bool
  default     = true
}

# VPC configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Number of availability zones to use"
  type        = number
  default     = 2
}

# KMS configuration
variable "kms_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 7
}