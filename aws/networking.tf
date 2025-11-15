# VPC (equivalent to Azure Virtual Network)
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = local.naming.vpc
  })
}

# Internet Gateway (for NAT Gateway access)
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.naming.vpc}-igw"
  })
}

# Private Subnets (equivalent to Azure private subnet)
resource "aws_subnet" "private" {
  count = length(local.azs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnets[count.index]
  availability_zone = local.azs[count.index]

  # Prevent automatic public IP assignment
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${local.naming.private_subnet_prefix}-${count.index + 1}"
    Type = "Private"
    Tier = "Application"
  })
}

# Database Subnets (equivalent to Azure delegated subnet)
resource "aws_subnet" "database" {
  count = length(local.azs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.database_subnets[count.index]
  availability_zone = local.azs[count.index]

  # Prevent automatic public IP assignment
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${local.naming.database_subnet_prefix}-${count.index + 1}"
    Type = "Private"
    Tier = "Database"
  })
}

# Public Subnets for NAT Gateways (minimal public exposure)
resource "aws_subnet" "public" {
  count = length(local.azs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 20)
  availability_zone = local.azs[count.index]

  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.naming.vpc}-public-${count.index + 1}"
    Type = "Public"
    Tier = "NAT"
  })
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count = length(local.azs)

  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.naming.vpc}-nat-eip-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.main]
}

# NAT Gateways for private subnet internet access
resource "aws_nat_gateway" "main" {
  count = length(local.azs)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, {
    Name = "${local.naming.vpc}-nat-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.main]
}

# Route Table for Public Subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.naming.vpc}-public-rt"
  })
}

# Route Tables for Private Subnets
resource "aws_route_table" "private" {
  count = length(local.azs)

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(local.common_tags, {
    Name = "${local.naming.vpc}-private-rt-${count.index + 1}"
  })
}

# Route Table for Database Subnets (no internet access)
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.naming.vpc}-database-rt"
  })
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table_association" "database" {
  count = length(aws_subnet.database)

  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database.id
}

# Security Group for Database (equivalent to Azure NSG for private subnet)
resource "aws_security_group" "database" {
  name_prefix = "${local.naming.security_group_prefix}-database"
  vpc_id      = aws_vpc.main.id
  description = "Security group for database instances"

  # Allow PostgreSQL traffic from private subnets only
  ingress {
    description = "PostgreSQL from private subnets"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = local.private_subnets
  }

  # Allow traffic within database subnet group
  ingress {
    description = "Internal database communication"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = local.database_subnets
  }

  # Outbound rules - allow all (for updates, etc.)
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.naming.security_group_prefix}-database-sg"
  })
}

# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${local.naming.security_group_prefix}-endpoints"
  vpc_id      = aws_vpc.main.id
  description = "Security group for VPC endpoints"

  # Allow HTTPS traffic from VPC
  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow DNS traffic from VPC
  ingress {
    description = "DNS from VPC"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.naming.security_group_prefix}-endpoints-sg"
  })
}

# VPC Endpoints for AWS services (equivalent to Azure Private Endpoints)
resource "aws_vpc_endpoint" "s3" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type   = "Gateway"
  route_table_ids     = concat(aws_route_table.private[*].id, [aws_route_table.database.id])
  policy              = data.aws_iam_policy_document.s3_vpc_endpoint.json

  tags = merge(local.common_tags, {
    Name = "${local.naming.vpc}-s3-endpoint"
  })
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  policy              = data.aws_iam_policy_document.secretsmanager_vpc_endpoint.json

  tags = merge(local.common_tags, {
    Name = "${local.naming.vpc}-secretsmanager-endpoint"
  })
}

resource "aws_vpc_endpoint" "monitoring" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.monitoring"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${local.naming.vpc}-monitoring-endpoint"
  })
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${local.naming.vpc}-logs-endpoint"
  })
}

# IAM Policies for VPC Endpoints
data "aws_iam_policy_document" "s3_vpc_endpoint" {
  statement {
    effect = "Allow"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::${local.naming.s3_bucket_prefix}*",
      "arn:aws:s3:::${local.naming.s3_bucket_prefix}*/*"
    ]
  }
}

data "aws_iam_policy_document" "secretsmanager_vpc_endpoint" {
  statement {
    effect = "Allow"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "secretsmanager:ResourceTag/Environment"
      values   = [var.environment]
    }
  }
}

# Network ACLs for additional security layer (equivalent to Azure NSG rules)
resource "aws_network_acl" "database" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.database[*].id

  # Allow PostgreSQL from private subnets
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = local.private_subnets[0]
    from_port  = 5432
    to_port    = 5432
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 101
    action     = "allow"
    cidr_block = local.private_subnets[1]
    from_port  = 5432
    to_port    = 5432
  }

  # Allow return traffic
  ingress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Egress rules
  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  tags = merge(local.common_tags, {
    Name = "${local.naming.vpc}-database-nacl"
  })
}