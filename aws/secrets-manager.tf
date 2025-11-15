# KMS Key for encryption (equivalent to Azure Key Vault encryption)
resource "aws_kms_key" "main" {
  description             = "KMS key for ${var.project_name} ${var.environment} environment"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true

  # Key policy - restrict access to current AWS account
  policy = data.aws_iam_policy_document.kms_key_policy.json

  tags = merge(local.common_tags, {
    Name = local.naming.kms_key
  })
}

# KMS Key Alias
resource "aws_kms_alias" "main" {
  name          = "alias/${local.naming.kms_key}"
  target_key_id = aws_kms_key.main.key_id
}

# KMS Key Policy (equivalent to Azure Key Vault access policies)
data "aws_iam_policy_document" "kms_key_policy" {
  # Allow root account full access (equivalent to Key Vault Administrator)
  statement {
    sid    = "EnableRootAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Allow current user/role administrative access
  statement {
    sid    = "EnableAdministrativeAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current.arn]
    }
    actions = [
      "kms:Create*",
      "kms:Describe*",
      "kms:Enable*",
      "kms:List*",
      "kms:Put*",
      "kms:Update*",
      "kms:Revoke*",
      "kms:Disable*",
      "kms:Get*",
      "kms:Delete*",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion"
    ]
    resources = ["*"]
  }

  # Allow services to use the key for encryption/decryption
  statement {
    sid    = "EnableServiceAccess"
    effect = "Allow"
    principals {
      type = "AWS"
      identifiers = [
        data.aws_caller_identity.current.arn
      ]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
  }

  # Allow AWS services to use the key
  statement {
    sid    = "AllowAWSServices"
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = [
        "secretsmanager.amazonaws.com",
        "rds.amazonaws.com",
        "s3.amazonaws.com",
        "logs.amazonaws.com"
      ]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values = [
        "secretsmanager.${var.region}.amazonaws.com",
        "rds.${var.region}.amazonaws.com",
        "s3.${var.region}.amazonaws.com",
        "logs.${var.region}.amazonaws.com"
      ]
    }
  }
}

# Generate PostgreSQL admin password (equivalent to Azure random_password)
resource "random_password" "postgresql_admin_password" {
  length  = 32
  special = true
}

# Secrets Manager Secret for PostgreSQL password (equivalent to Azure Key Vault secret)
resource "aws_secretsmanager_secret" "postgresql_password" {
  name                    = "${local.naming.secrets_manager}/postgresql-admin-password"
  description             = "PostgreSQL administrator password for ${var.project_name} ${var.environment}"
  kms_key_id              = aws_kms_key.main.arn
  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  replica {
    region = var.region
  }

  tags = merge(local.common_tags, {
    Name        = "${local.naming.secrets_manager}/postgresql-admin-password"
    SecretType  = "database-password"
    Service     = "postgresql"
  })
}

# Store the PostgreSQL password in Secrets Manager
resource "aws_secretsmanager_secret_version" "postgresql_password" {
  secret_id = aws_secretsmanager_secret.postgresql_password.id
  secret_string = jsonencode({
    username = var.postgresql_admin_username
    password = random_password.postgresql_admin_password.result
  })
}

# Secrets Manager Secret for application configuration (equivalent to additional Key Vault secrets)
resource "aws_secretsmanager_secret" "app_config" {
  name                    = "${local.naming.secrets_manager}/application-config"
  description             = "Application configuration secrets for ${var.project_name} ${var.environment}"
  kms_key_id              = aws_kms_key.main.arn
  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = merge(local.common_tags, {
    Name        = "${local.naming.secrets_manager}/application-config"
    SecretType  = "application-config"
    Service     = "application"
  })
}

# Store application configuration (placeholder - customize as needed)
resource "aws_secretsmanager_secret_version" "app_config" {
  secret_id = aws_secretsmanager_secret.app_config.id
  secret_string = jsonencode({
    environment         = var.environment
    database_url        = "postgresql://${var.postgresql_admin_username}:${random_password.postgresql_admin_password.result}@${aws_db_instance.main.endpoint}:${aws_db_instance.main.port}/${aws_db_instance.main.db_name}"
    s3_bucket          = aws_s3_bucket.main.bucket
    log_group          = aws_cloudwatch_log_group.main.name
  })

  depends_on = [
    aws_db_instance.main,
    aws_s3_bucket.main,
    aws_cloudwatch_log_group.main
  ]
}

# IAM Role for applications to access secrets (equivalent to Azure RBAC)
resource "aws_iam_role" "secrets_reader" {
  name = "${local.naming.secrets_manager}-reader-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "ec2.amazonaws.com",
            "ecs-tasks.amazonaws.com",
            "lambda.amazonaws.com"
          ]
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM Policy for reading secrets (equivalent to Azure Key Vault Secrets User)
resource "aws_iam_policy" "secrets_reader" {
  name        = "${local.naming.secrets_manager}-reader-policy"
  description = "Policy to read secrets from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.postgresql_password.arn,
          aws_secretsmanager_secret.app_config.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = [aws_kms_key.main.arn]
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${var.region}.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "secrets_reader" {
  role       = aws_iam_role.secrets_reader.name
  policy_arn = aws_iam_policy.secrets_reader.arn
}

# Instance profile for EC2 instances (if needed)
resource "aws_iam_instance_profile" "secrets_reader" {
  name = "${local.naming.secrets_manager}-reader-profile"
  role = aws_iam_role.secrets_reader.name

  tags = local.common_tags
}

# Secrets Manager Secret Rotation (equivalent to Azure Key Vault secret rotation)
resource "aws_secretsmanager_secret_rotation" "postgresql_password" {
  count = var.environment == "prod" ? 1 : 0

  secret_id           = aws_secretsmanager_secret.postgresql_password.id
  rotation_lambda_arn = aws_lambda_function.rotate_secret[0].arn

  rotation_rules {
    automatically_after_days = 30
  }

  depends_on = [aws_lambda_permission.secrets_manager]
}

# Lambda function for secret rotation (production environments)
resource "aws_lambda_function" "rotate_secret" {
  count = var.environment == "prod" ? 1 : 0

  filename         = "secret_rotation.zip"
  function_name    = "${local.naming.secrets_manager}-rotation"
  role            = aws_iam_role.lambda_rotation[0].arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip[0].output_base64sha256
  runtime         = "python3.9"
  timeout         = 30

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda_rotation[0].id]
  }

  environment {
    variables = {
      SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${var.region}.amazonaws.com"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.naming.secrets_manager}-rotation"
  })
}

# Lambda deployment package
data "archive_file" "lambda_zip" {
  count = var.environment == "prod" ? 1 : 0

  type        = "zip"
  output_path = "secret_rotation.zip"
  source {
    content = <<EOF
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    logger.info("Secret rotation function called")
    # Implement secret rotation logic here
    return {
        'statusCode': 200,
        'body': json.dumps('Secret rotation completed')
    }
EOF
    filename = "lambda_function.py"
  }
}

# IAM role for Lambda rotation function
resource "aws_iam_role" "lambda_rotation" {
  count = var.environment == "prod" ? 1 : 0

  name = "${local.naming.secrets_manager}-rotation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for Lambda rotation function
resource "aws_iam_policy" "lambda_rotation" {
  count = var.environment == "prod" ? 1 : 0

  name = "${local.naming.secrets_manager}-rotation-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage"
        ]
        Resource = aws_secretsmanager_secret.postgresql_password.arn
      }
    ]
  })

  tags = local.common_tags
}

# Attach rotation policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_rotation" {
  count = var.environment == "prod" ? 1 : 0

  role       = aws_iam_role.lambda_rotation[0].name
  policy_arn = aws_iam_policy.lambda_rotation[0].arn
}

# Security group for Lambda rotation function
resource "aws_security_group" "lambda_rotation" {
  count = var.environment == "prod" ? 1 : 0

  name_prefix = "${local.naming.security_group_prefix}-lambda-rotation"
  vpc_id      = aws_vpc.main.id
  description = "Security group for secret rotation Lambda"

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = local.database_subnets
  }

  tags = merge(local.common_tags, {
    Name = "${local.naming.security_group_prefix}-lambda-rotation-sg"
  })
}

# Lambda permission for Secrets Manager
resource "aws_lambda_permission" "secrets_manager" {
  count = var.environment == "prod" ? 1 : 0

  statement_id  = "AllowExecutionFromSecretsManager"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotate_secret[0].function_name
  principal     = "secretsmanager.amazonaws.com"
}