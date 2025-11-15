# CloudWatch Log Group for centralized logging (equivalent to Azure Log Analytics Workspace)
resource "aws_cloudwatch_log_group" "main" {
  name              = "/aws/${local.naming.cloudwatch_prefix}"
  retention_in_days = var.environment == "prod" ? 90 : 30
  kms_key_id        = aws_kms_key.main.arn

  tags = merge(local.common_tags, {
    Name = "${local.naming.cloudwatch_prefix}-main-logs"
  })
}

# CloudTrail for security audit logging (equivalent to Azure security monitoring)
resource "aws_cloudtrail" "main" {
  name           = local.naming.cloudwatch_prefix
  s3_bucket_name = aws_s3_bucket.cloudtrail_logs.id

  # Enable log file validation
  enable_log_file_validation = true

  # Include global services like IAM
  include_global_service_events = true
  is_multi_region_trail         = true

  # CloudWatch Logs integration
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail.arn

  # KMS encryption
  kms_key_id = aws_kms_key.main.arn

  # Event selectors for data events (S3, Secrets Manager)
  event_selector {
    read_write_type                 = "All"
    include_management_events       = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.main.arn}/*"]
    }

    data_resource {
      type   = "AWS::SecretsManager::Secret"
      values = ["*"]
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.naming.cloudwatch_prefix}-cloudtrail"
  })

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]
}

# Dedicated S3 bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket        = "${local.naming.s3_bucket_prefix}cloudtrail${random_integer.s3_suffix.result}"
  force_destroy = var.environment != "prod"

  tags = merge(local.common_tags, {
    Name = "${local.naming.s3_bucket_prefix}cloudtrail${random_integer.s3_suffix.result}"
    Type = "CloudTrailLogs"
  })
}

# CloudTrail S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.main.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# CloudTrail S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudTrail S3 bucket policy
resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket_policy.json

  depends_on = [aws_s3_bucket_public_access_block.cloudtrail_logs]
}

# CloudTrail bucket policy document
data "aws_iam_policy_document" "cloudtrail_bucket_policy" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail_logs.arn]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = ["arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/${local.naming.cloudwatch_prefix}"]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail_logs.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = ["arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/${local.naming.cloudwatch_prefix}"]
    }
  }
}

# CloudWatch Log Group for CloudTrail
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/${local.naming.cloudwatch_prefix}"
  retention_in_days = var.environment == "prod" ? 90 : 30
  kms_key_id        = aws_kms_key.main.arn

  tags = merge(local.common_tags, {
    Name = "${local.naming.cloudwatch_prefix}-cloudtrail-logs"
  })
}

# IAM role for CloudTrail to CloudWatch Logs
resource "aws_iam_role" "cloudtrail" {
  name = "${local.naming.cloudwatch_prefix}-cloudtrail-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for CloudTrail to write to CloudWatch Logs
resource "aws_iam_policy" "cloudtrail" {
  name = "${local.naming.cloudwatch_prefix}-cloudtrail-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach CloudTrail policy to role
resource "aws_iam_role_policy_attachment" "cloudtrail" {
  role       = aws_iam_role.cloudtrail.name
  policy_arn = aws_iam_policy.cloudtrail.arn
}

# SNS Topic for alerts (equivalent to Azure Action Groups)
resource "aws_sns_topic" "alerts" {
  name              = "${local.naming.cloudwatch_prefix}-alerts"
  kms_master_key_id = aws_kms_key.main.arn

  tags = merge(local.common_tags, {
    Name = "${local.naming.cloudwatch_prefix}-alerts"
  })
}

# SNS Topic Policy
resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = "SNS:Publish"
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}

# SNS Topic for security alerts
resource "aws_sns_topic" "security_alerts" {
  name              = "${local.naming.cloudwatch_prefix}-security-alerts"
  kms_master_key_id = aws_kms_key.main.arn

  tags = merge(local.common_tags, {
    Name = "${local.naming.cloudwatch_prefix}-security-alerts"
    Type = "SecurityAlerts"
  })
}

# Example SNS subscription (customize email as needed)
resource "aws_sns_topic_subscription" "security_email" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = "security@yourdomain.com" # Change this to your email
}

resource "aws_sns_topic_subscription" "operational_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "ops@yourdomain.com" # Change this to your email
}

# CloudWatch Log Metric Filters for Security Monitoring
resource "aws_cloudwatch_log_metric_filter" "failed_secret_access" {
  name           = "${local.naming.cloudwatch_prefix}-failed-secret-access"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.eventSource = secretsmanager.amazonaws.com) && ($.errorCode EXISTS) }"

  metric_transformation {
    name      = "FailedSecretAccess"
    namespace = "Security/SecretsManager"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "unauthorized_api_calls" {
  name           = "${local.naming.cloudwatch_prefix}-unauthorized-api-calls"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.errorCode = \"*UnauthorizedOperation\") || ($.errorCode = \"AccessDenied*\") }"

  metric_transformation {
    name      = "UnauthorizedAPICalls"
    namespace = "Security/CloudTrail"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "root_account_usage" {
  name           = "${local.naming.cloudwatch_prefix}-root-account-usage"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"

  metric_transformation {
    name      = "RootAccountUsage"
    namespace = "Security/IAM"
    value     = "1"
  }
}

# CloudWatch Alarms for Security Events (equivalent to Azure security alerts)
resource "aws_cloudwatch_metric_alarm" "failed_secret_access" {
  alarm_name          = "${local.naming.cloudwatch_prefix}-failed-secret-access"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "FailedSecretAccess"
  namespace           = "Security/SecretsManager"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Failed attempts to access secrets"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  ok_actions          = [aws_sns_topic.security_alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "unauthorized_api_calls" {
  alarm_name          = "${local.naming.cloudwatch_prefix}-unauthorized-api-calls"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "UnauthorizedAPICalls"
  namespace           = "Security/CloudTrail"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "High number of unauthorized API calls"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "root_account_usage" {
  alarm_name          = "${local.naming.cloudwatch_prefix}-root-account-usage"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "RootAccountUsage"
  namespace           = "Security/IAM"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Root account is being used"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = local.common_tags
}

# CloudWatch Alarms for S3 Security (equivalent to Azure storage unusual access patterns)
resource "aws_cloudwatch_metric_alarm" "s3_high_error_rate" {
  alarm_name          = "${local.naming.cloudwatch_prefix}-s3-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4xxErrors"
  namespace           = "AWS/S3"
  period              = "300"
  statistic           = "Sum"
  threshold           = "50"
  alarm_description   = "High error rate on S3 bucket"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]

  dimensions = {
    BucketName = aws_s3_bucket.main.bucket
  }

  tags = local.common_tags
}

# AWS Config for compliance monitoring (equivalent to Azure policy compliance)
resource "aws_config_configuration_recorder" "main" {
  name     = "${local.naming.cloudwatch_prefix}-config-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "${local.naming.cloudwatch_prefix}-config-delivery"
  s3_bucket_name = aws_s3_bucket.config_logs.bucket
}

# S3 bucket for AWS Config
resource "aws_s3_bucket" "config_logs" {
  bucket        = "${local.naming.s3_bucket_prefix}config${random_integer.s3_suffix.result}"
  force_destroy = var.environment != "prod"

  tags = merge(local.common_tags, {
    Name = "${local.naming.s3_bucket_prefix}config${random_integer.s3_suffix.result}"
    Type = "ConfigLogs"
  })
}

# Config S3 bucket policy
resource "aws_s3_bucket_policy" "config_logs" {
  bucket = aws_s3_bucket.config_logs.id
  policy = data.aws_iam_policy_document.config_bucket_policy.json
}

# Config bucket policy document
data "aws_iam_policy_document" "config_bucket_policy" {
  statement {
    sid    = "AWSConfigBucketPermissionsCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.config_logs.arn]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AWSConfigBucketExistenceCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.config_logs.arn]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AWSConfigBucketDelivery"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.config_logs.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# IAM role for AWS Config
resource "aws_iam_role" "config" {
  name = "${local.naming.cloudwatch_prefix}-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach AWS managed policy for Config
resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/ConfigRole"
}

# Custom CloudWatch Dashboard (equivalent to Azure Workbook)
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.naming.cloudwatch_prefix}-security-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["Security/SecretsManager", "FailedSecretAccess"],
            ["Security/CloudTrail", "UnauthorizedAPICalls"],
            ["Security/IAM", "RootAccountUsage"]
          ]
          period = 300
          stat   = "Sum"
          region = var.region
          title  = "Security Metrics"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.main.identifier],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.main.identifier]
          ]
          period = 300
          stat   = "Average"
          region = var.region
          title  = "Database Metrics"
          view   = "timeSeries"
        }
      }
    ]
  })

  # CloudWatch dashboards don't support tags
}