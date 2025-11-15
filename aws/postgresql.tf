# DB Subnet Group (equivalent to Azure delegated subnet)
resource "aws_db_subnet_group" "main" {
  name       = local.naming.rds_instance
  subnet_ids = aws_subnet.database[*].id

  tags = merge(local.common_tags, {
    Name = "${local.naming.rds_instance}-subnet-group"
  })
}

# DB Parameter Group for PostgreSQL configuration (equivalent to Azure server configuration)
resource "aws_db_parameter_group" "main" {
  family = "postgres15"
  name   = "${local.naming.rds_instance}-params"

  # Enhanced security and logging parameters (equivalent to Azure PostgreSQL configuration)
  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_checkpoints"
    value = "1"
  }

  parameter {
    name  = "log_lock_waits"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # Log queries taking longer than 1 second
  }

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  parameter {
    name  = "log_statement"
    value = "ddl" # Log DDL statements
  }

  parameter {
    name  = "log_min_messages"
    value = "warning"
  }

  # Performance tuning parameters
  parameter {
    name  = "shared_buffers"
    value = "{DBInstanceClassMemory/4}" # 25% of instance memory
  }

  parameter {
    name  = "effective_cache_size"
    value = "{DBInstanceClassMemory*3/4}" # 75% of instance memory
  }

  tags = merge(local.common_tags, {
    Name = "${local.naming.rds_instance}-parameter-group"
  })
}

# DB Option Group (for PostgreSQL extensions if needed)
resource "aws_db_option_group" "main" {
  name                 = "${local.naming.rds_instance}-options"
  option_group_description = "Option group for ${local.naming.rds_instance}"
  engine_name          = "postgres"
  major_engine_version = "15"

  tags = merge(local.common_tags, {
    Name = "${local.naming.rds_instance}-option-group"
  })
}

# RDS Instance (equivalent to Azure PostgreSQL Flexible Server)
resource "aws_db_instance" "main" {
  # Basic configuration
  identifier = local.naming.rds_instance
  engine     = "postgres"
  engine_version = "15.4"

  # Instance specifications
  instance_class        = var.postgresql_instance_class
  allocated_storage     = var.postgresql_allocated_storage
  max_allocated_storage = var.postgresql_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id           = aws_kms_key.main.arn

  # Database configuration
  db_name  = replace("${var.project_name}_${var.environment}", "-", "_")
  username = var.postgresql_admin_username
  password = random_password.postgresql_admin_password.result

  # Network configuration - private access only
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false
  port                   = 5432

  # Configuration groups
  parameter_group_name = aws_db_parameter_group.main.name
  option_group_name    = aws_db_option_group.main.name

  # Backup configuration (equivalent to Azure backup settings)
  backup_retention_period   = var.environment == "prod" ? 35 : 7
  backup_window             = "03:00-04:00"
  maintenance_window        = "sun:04:00-sun:05:00"
  auto_minor_version_upgrade = true
  deletion_protection       = var.environment == "prod" ? true : false

  # Enhanced monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  # Performance Insights
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.main.arn
  performance_insights_retention_period = var.environment == "prod" ? 731 : 7

  # Enable CloudWatch logs export (equivalent to Azure diagnostic settings)
  enabled_cloudwatch_logs_exports = ["postgresql"]

  # Multi-AZ for production (equivalent to Azure high availability)
  multi_az = var.environment == "prod" ? true : false

  # Final snapshot configuration
  final_snapshot_identifier = var.environment == "prod" ? "${local.naming.rds_instance}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null
  skip_final_snapshot      = var.environment == "prod" ? false : true

  # Copy tags to snapshots
  copy_tags_to_snapshot = true

  tags = merge(local.common_tags, {
    Name = local.naming.rds_instance
  })

  depends_on = [
    aws_db_subnet_group.main,
    aws_security_group.database,
    aws_db_parameter_group.main,
    aws_db_option_group.main,
    aws_iam_role.rds_monitoring
  ]
}

# Read Replica for production (equivalent to Azure geo-redundant backup)
resource "aws_db_instance" "replica" {
  count = var.environment == "prod" ? 1 : 0

  identifier             = "${local.naming.rds_instance}-replica"
  replicate_source_db    = aws_db_instance.main.identifier
  instance_class         = var.postgresql_instance_class
  publicly_accessible    = false
  auto_minor_version_upgrade = true

  # Enhanced monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  # Performance Insights
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.main.arn
  performance_insights_retention_period = 731

  tags = merge(local.common_tags, {
    Name = "${local.naming.rds_instance}-replica"
    Type = "ReadReplica"
  })
}

# IAM Role for RDS Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "${local.naming.rds_instance}-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach AWS managed policy for RDS Enhanced Monitoring
resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# CloudWatch Log Group for PostgreSQL logs
resource "aws_cloudwatch_log_group" "postgresql" {
  name              = "/aws/rds/instance/${local.naming.rds_instance}/postgresql"
  retention_in_days = var.environment == "prod" ? 90 : 30
  kms_key_id        = aws_kms_key.main.arn

  tags = merge(local.common_tags, {
    Name = "${local.naming.rds_instance}-postgresql-logs"
  })
}

# CloudWatch Alarms for RDS monitoring (equivalent to Azure monitoring alerts)
resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  alarm_name          = "${local.naming.rds_instance}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors RDS CPU utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "database_connections" {
  alarm_name          = "${local.naming.rds_instance}-high-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors RDS connection count"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "database_freeable_memory" {
  alarm_name          = "${local.naming.rds_instance}-low-freeable-memory"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "100000000" # 100MB in bytes
  alarm_description   = "This metric monitors RDS freeable memory"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  tags = local.common_tags
}

# DB Snapshot (equivalent to Azure backup)
resource "aws_db_snapshot" "main" {
  count = var.environment == "prod" ? 1 : 0

  db_instance_identifier = aws_db_instance.main.identifier
  db_snapshot_identifier = "${local.naming.rds_instance}-initial-snapshot"

  tags = merge(local.common_tags, {
    Name = "${local.naming.rds_instance}-initial-snapshot"
    Type = "InitialSnapshot"
  })
}