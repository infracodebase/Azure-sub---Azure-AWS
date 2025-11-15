# Generate random suffix for S3 bucket name (must be globally unique)
resource "random_integer" "s3_suffix" {
  min = 100
  max = 999
}

# S3 Bucket (equivalent to Azure Storage Account)
resource "aws_s3_bucket" "main" {
  bucket = "${local.naming.s3_bucket_prefix}${random_integer.s3_suffix.result}"

  tags = merge(local.common_tags, {
    Name = "${local.naming.s3_bucket_prefix}${random_integer.s3_suffix.result}"
  })
}

# S3 Bucket Versioning (equivalent to Azure Storage versioning)
resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id

  versioning_configuration {
    status = var.s3_versioning ? "Enabled" : "Disabled"
  }
}

# S3 Bucket Server-Side Encryption (equivalent to Azure Storage encryption)
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.main.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket Public Access Block (equivalent to Azure allowBlobPublicAccess: false)
resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket Policy (restrictive access policy)
resource "aws_s3_bucket_policy" "main" {
  bucket = aws_s3_bucket.main.id
  policy = data.aws_iam_policy_document.s3_bucket_policy.json

  depends_on = [aws_s3_bucket_public_access_block.main]
}

# S3 Bucket Policy Document (equivalent to Azure network access restrictions)
data "aws_iam_policy_document" "s3_bucket_policy" {
  # Deny all public access
  statement {
    sid    = "DenyPublicAccess"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.main.arn,
      "${aws_s3_bucket.main.arn}/*"
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Allow access only from VPC endpoints
  statement {
    sid    = "AllowVPCEndpointAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.main.arn,
      "${aws_s3_bucket.main.arn}/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceVpce"
      values   = [aws_vpc_endpoint.s3.id]
    }
  }

  # Allow access from specific IP addresses if provided
  dynamic "statement" {
    for_each = length(var.allowed_ip_addresses) > 0 ? [1] : []
    content {
      sid    = "AllowSpecificIPs"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = ["*"]
      }
      actions = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      resources = [
        aws_s3_bucket.main.arn,
        "${aws_s3_bucket.main.arn}/*"
      ]
      condition {
        test     = "IpAddress"
        variable = "aws:SourceIp"
        values   = var.allowed_ip_addresses
      }
      condition {
        test     = "Bool"
        variable = "aws:SecureTransport"
        values   = ["true"]
      }
    }
  }
}

# S3 Bucket Logging (equivalent to Azure Storage logging)
resource "aws_s3_bucket_logging" "main" {
  bucket = aws_s3_bucket.main.id

  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "access-logs/"
}

# Separate bucket for access logs
resource "aws_s3_bucket" "access_logs" {
  bucket = "${local.naming.s3_bucket_prefix}logs${random_integer.s3_suffix.result}"

  tags = merge(local.common_tags, {
    Name = "${local.naming.s3_bucket_prefix}logs${random_integer.s3_suffix.result}"
    Type = "AccessLogs"
  })
}

# Access logs bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.main.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# Access logs bucket public access block
resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Note: S3 bucket notifications to CloudWatch Events are configured via EventBridge
# This would require additional EventBridge configuration for monitoring S3 events

# S3 Bucket Lifecycle Configuration (equivalent to Azure storage management policy)
resource "aws_s3_bucket_lifecycle_configuration" "main" {
  count = var.s3_lifecycle_enabled ? 1 : 0

  bucket = aws_s3_bucket.main.id

  # Main objects lifecycle
  rule {
    id     = "main_lifecycle"
    status = "Enabled"

    filter {}

    # Transition to Infrequent Access after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Transition to Deep Archive after 180 days
    transition {
      days          = 180
      storage_class = "DEEP_ARCHIVE"
    }

    # Delete objects after 365 days (customize as needed)
    expiration {
      days = 365
    }
  }

  # Non-current version lifecycle
  rule {
    id     = "noncurrent_version_lifecycle"
    status = "Enabled"

    filter {}

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  # Incomplete multipart uploads cleanup
  rule {
    id     = "incomplete_multipart_uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.main]
}

# S3 Bucket Intelligent Tiering (optimize storage costs)
resource "aws_s3_bucket_intelligent_tiering_configuration" "main" {
  bucket = aws_s3_bucket.main.id
  name   = "main_intelligent_tiering"

  status = "Enabled"

  # Apply to all objects
  filter {
    prefix = ""
  }

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }
}

# S3 Bucket CORS Configuration (if needed for web applications)
resource "aws_s3_bucket_cors_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["https://*.${var.project_name}.com"] # Customize as needed
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# S3 Bucket Replication (equivalent to Azure geo-redundant storage)
resource "aws_s3_bucket_replication_configuration" "main" {
  count = var.environment == "prod" ? 1 : 0

  role   = aws_iam_role.s3_replication[0].arn
  bucket = aws_s3_bucket.main.id

  rule {
    id     = "main_replication"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.replica[0].arn
      storage_class = "STANDARD_IA"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.replica[0].arn
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.main]
}

# Replica bucket for cross-region replication (production only)
resource "aws_s3_bucket" "replica" {
  count = var.environment == "prod" ? 1 : 0

  # Different region for disaster recovery
  provider = aws.replica
  bucket   = "${local.naming.s3_bucket_prefix}replica${random_integer.s3_suffix.result}"

  tags = merge(local.common_tags, {
    Name = "${local.naming.s3_bucket_prefix}replica${random_integer.s3_suffix.result}"
    Type = "Replica"
  })
}

# Replica bucket versioning
resource "aws_s3_bucket_versioning" "replica" {
  count = var.environment == "prod" ? 1 : 0

  provider = aws.replica
  bucket   = aws_s3_bucket.replica[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

# KMS key for replica bucket
resource "aws_kms_key" "replica" {
  count = var.environment == "prod" ? 1 : 0

  provider                = aws.replica
  description             = "KMS key for S3 replica bucket"
  deletion_window_in_days = var.kms_deletion_window

  tags = merge(local.common_tags, {
    Name = "${local.naming.kms_key}-replica"
  })
}

# KMS alias for replica
resource "aws_kms_alias" "replica" {
  count = var.environment == "prod" ? 1 : 0

  provider      = aws.replica
  name          = "alias/${local.naming.kms_key}-replica"
  target_key_id = aws_kms_key.replica[0].key_id
}

# IAM role for S3 replication
resource "aws_iam_role" "s3_replication" {
  count = var.environment == "prod" ? 1 : 0

  name = "${local.naming.s3_bucket_prefix}-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for S3 replication
resource "aws_iam_policy" "s3_replication" {
  count = var.environment == "prod" ? 1 : 0

  name = "${local.naming.s3_bucket_prefix}-replication-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl"
        ]
        Resource = "${aws_s3_bucket.main.arn}/*"
      },
      {
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = aws_s3_bucket.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete"
        ]
        Resource = "${aws_s3_bucket.replica[0].arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.replica[0].arn
      }
    ]
  })

  tags = local.common_tags
}

# Attach replication policy to role
resource "aws_iam_role_policy_attachment" "s3_replication" {
  count = var.environment == "prod" ? 1 : 0

  role       = aws_iam_role.s3_replication[0].name
  policy_arn = aws_iam_policy.s3_replication[0].arn
}

# Provider for replica region (production only)
provider "aws" {
  alias  = "replica"
  region = var.region == "us-east-2" ? "us-west-2" : "us-east-2"

  default_tags {
    tags = var.tags
  }
}

# CloudWatch metric filters for S3 (equivalent to Azure storage monitoring)
resource "aws_cloudwatch_log_metric_filter" "s3_access_errors" {
  name           = "${local.naming.s3_bucket_prefix}-access-errors"
  log_group_name = aws_cloudwatch_log_group.s3_access.name
  pattern        = "ERROR"

  metric_transformation {
    name      = "S3AccessErrors"
    namespace = "Custom/S3"
    value     = "1"
  }
}

# CloudWatch log group for S3 access logs
resource "aws_cloudwatch_log_group" "s3_access" {
  name              = "/aws/s3/${aws_s3_bucket.main.bucket}"
  retention_in_days = var.environment == "prod" ? 90 : 30
  kms_key_id        = aws_kms_key.main.arn

  tags = merge(local.common_tags, {
    Name = "${aws_s3_bucket.main.bucket}-access-logs"
  })
}