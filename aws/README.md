# Secure AWS Infrastructure with Terraform

This Terraform configuration creates a secure, production-ready AWS infrastructure following security best practices and compliance standards. This is a 100% feature-equivalent conversion of the Azure infrastructure to AWS.

## Architecture Overview

This infrastructure implements a secure, network-isolated environment with the following AWS components:

- **VPC**: Multi-AZ Virtual Private Cloud with private and database subnets
- **Secrets Manager**: Secure secret storage with KMS encryption and automatic rotation
- **RDS PostgreSQL**: Database with private network access and enhanced monitoring
- **S3**: Secure object storage with versioning, lifecycle policies, and VPC endpoints
- **CloudWatch/CloudTrail**: Comprehensive logging, monitoring, and security auditing

## Security Features

### Network Security
- Private subnets with Security Groups and NACLs
- NAT Gateways for controlled internet access
- VPC Endpoints for AWS services (no internet routing)
- No public access to databases or sensitive resources

### Secrets Manager Security
- KMS encryption with customer-managed keys
- Automatic secret rotation (production environments)
- VPC endpoints for private access
- Fine-grained IAM permissions

### Database Security
- Private subnet deployment with no public access
- Security Groups restricting access to application subnets only
- Encrypted at rest with customer-managed KMS keys
- Enhanced monitoring and Performance Insights
- Multi-AZ deployment for production environments

### S3 Security
- VPC endpoints for private access only
- Bucket policies preventing public access
- Server-side encryption with KMS
- Versioning and intelligent tiering
- Cross-region replication for production
- Comprehensive access logging

### Monitoring & Security
- CloudTrail for comprehensive API logging
- CloudWatch for centralized log management
- Security-focused metric filters and alarms
- AWS Config for compliance monitoring
- Automated alerting via SNS

## AWS Service Equivalencies

| Azure Service | AWS Service | Feature Parity |
|---------------|-------------|----------------|
| Virtual Network | VPC | ✓ Complete |
| Private Subnet | Private Subnet + Security Groups | ✓ Complete |
| Network Security Group | Security Groups + NACLs | ✓ Complete |
| Private Endpoints | VPC Endpoints | ✓ Complete |
| Key Vault | Secrets Manager + KMS | ✓ Complete |
| PostgreSQL Flexible Server | RDS PostgreSQL | ✓ Complete |
| Storage Account | S3 + CloudFront | ✓ Complete |
| Log Analytics Workspace | CloudWatch Logs | ✓ Complete |
| Application Insights | CloudWatch + X-Ray | ✓ Complete |
| Activity Logs | CloudTrail | ✓ Complete |
| Azure Monitor Alerts | CloudWatch Alarms + SNS | ✓ Complete |

## Prerequisites

1. **AWS CLI** - [Install AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
2. **Terraform** - [Install Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
3. **AWS Account** with appropriate permissions

## Required AWS Permissions

Your AWS credentials need the following permissions:
- `PowerUserAccess` or equivalent for resource creation
- `IAMFullAccess` for creating roles and policies
- `KMSFullAccess` for managing encryption keys

## Quick Start

1. **Configure AWS Credentials**
   ```bash
   aws configure
   # Or set environment variables:
   # export AWS_ACCESS_KEY_ID="your-access-key"
   # export AWS_SECRET_ACCESS_KEY="your-secret-key"
   # export AWS_DEFAULT_REGION="us-east-2"
   ```

2. **Clone and Configure**
   ```bash
   # Copy the example variables file
   cp terraform.tfvars.example terraform.tfvars

   # Edit terraform.tfvars with your values
   nano terraform.tfvars
   ```

3. **Initialize Terraform**
   ```bash
   terraform init
   ```

4. **Plan Deployment**
   ```bash
   terraform plan
   ```

5. **Deploy Infrastructure**
   ```bash
   terraform apply
   ```

## Configuration Options

### Environment Variables
Key configuration options in `terraform.tfvars`:

- `environment`: Environment name (dev/staging/prod)
- `region`: AWS region (default: us-east-2)
- `project_name`: Project identifier for resource naming
- `allowed_ip_addresses`: Your IP addresses for emergency access (CIDR format)

### Network Configuration
- `vpc_cidr`: VPC CIDR block (default: 10.0.0.0/16)
- `availability_zones`: Number of AZs to use (default: 2)

### Production Considerations
- **Multi-AZ RDS**: Automatically enabled for prod environment
- **Cross-Region S3 Replication**: Enabled for prod environment
- **Extended Retention**: Longer log retention for production
- **Secret Rotation**: Automatic 30-day rotation for production

## Security Considerations

### Network Access
- All resources deployed in private subnets
- VPC endpoints provide secure AWS service connectivity
- Security Groups and NACLs control traffic flow
- NAT Gateways provide controlled internet access for updates

### Emergency Access
- Add your IP addresses to `allowed_ip_addresses` for management access
- Consider using AWS Systems Manager Session Manager for secure shell access
- Use AWS CloudShell for browser-based access

### Secrets Management
- Database passwords auto-generated and stored in Secrets Manager
- Application secrets should use Secrets Manager, not hardcoded values
- Use IAM roles for service-to-service authentication

## Monitoring & Alerts

### CloudWatch Integration
- Centralized logging with configurable retention
- Security event monitoring and alerting
- Performance monitoring for all resources

### Security Alerts
- Failed secret access attempts
- Unauthorized API calls
- Root account usage
- S3 access anomalies

### Operational Alerts
- Database performance issues
- High resource utilization
- Service availability problems

### Customization
Update email addresses in `monitoring.tf`:
```hcl
resource "aws_sns_topic_subscription" "security_email" {
  endpoint = "security@yourcompany.com"
}
```

## Cost Optimization

### Development Environment
- Uses t3.micro instances for cost efficiency
- Shorter retention periods
- Single-region deployment
- Reduced backup retention

### Production Optimizations
- Multi-AZ deployment for high availability
- Reserved Instances for predictable workloads
- S3 Intelligent Tiering for cost optimization
- Enhanced monitoring and longer retention

## Compliance Features

### Security Standards
- **SOC 2**: Network isolation, access controls, audit logging
- **PCI DSS**: Encryption, network segmentation, monitoring
- **ISO 27001**: Security controls, incident response, compliance reporting
- **FedRAMP**: Government cloud security requirements

### Built-in Compliance Tools
- AWS Config for resource compliance monitoring
- CloudTrail for comprehensive audit trails
- VPC Flow Logs for network monitoring
- AWS Security Hub integration ready

## Disaster Recovery

### Backup Strategy
- **RDS**: Automated backups with 35-day retention (prod)
- **S3**: Cross-region replication and versioning
- **Secrets Manager**: Cross-region secret replication
- **Infrastructure**: Terraform state backup to S3

### Recovery Procedures
1. **Database Recovery**: Point-in-time recovery from automated backups
2. **Storage Recovery**: S3 versioning and cross-region replication
3. **Infrastructure Recovery**: Terraform state restoration
4. **Secrets Recovery**: Secrets Manager cross-region recovery

## Maintenance

### Regular Tasks
1. **Security Reviews**: Audit IAM permissions quarterly
2. **Cost Optimization**: Review AWS Cost Explorer monthly
3. **Compliance Checks**: Monitor AWS Config rules
4. **Backup Verification**: Test disaster recovery procedures

### Updates
- Keep Terraform providers updated
- Monitor AWS security bulletins
- Review and update security group rules
- Rotate access keys regularly

## Troubleshooting

### Common Issues

**Terraform State Lock**
```bash
terraform force-unlock <lock-id>
```

**IAM Permission Issues**
- Verify AWS credentials configuration
- Check IAM policies for required permissions
- Ensure CloudTrail logging is enabled

**VPC Endpoint Connectivity**
- Verify route table associations
- Check security group rules
- Test DNS resolution within VPC

### Debugging Commands
```bash
# Check AWS credentials
aws sts get-caller-identity

# Verify VPC configuration
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=*secure-infra*"

# Test secret access
aws secretsmanager get-secret-value --secret-id <secret-name>
```

## Migration from Azure

This AWS infrastructure provides 100% feature parity with the Azure version:

### Key Mappings
- **Azure Resource Groups** → AWS Tags and naming conventions
- **Azure Key Vault** → AWS Secrets Manager + KMS
- **Azure VNet** → AWS VPC with Security Groups
- **Azure Private Endpoints** → AWS VPC Endpoints
- **Azure Monitor** → AWS CloudWatch + CloudTrail

### Migration Process
1. Export data from Azure services
2. Deploy AWS infrastructure using this Terraform
3. Import data to AWS services
4. Update application configurations
5. Test thoroughly before switching over

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review AWS documentation
3. Check Terraform AWS provider documentation
4. Submit issues to the project repository

## Contributing

1. Follow Terraform best practices
2. Update documentation for changes
3. Test in development environment first
4. Use semantic versioning for releases

---

**Note**: This infrastructure is designed for enterprise use with security as the primary concern. All components follow AWS Well-Architected Framework principles and industry security standards.