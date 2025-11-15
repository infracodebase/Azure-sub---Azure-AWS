# Secure Azure Infrastructure with Terraform

This Terraform configuration creates a secure, production-ready Azure infrastructure following security best practices and compliance standards.

## Architecture Overview

This infrastructure implements a secure, network-isolated environment with the following components:

- **Virtual Network**: Segmented subnets for application resources and private endpoints
- **Key Vault**: Secure secret storage with RBAC and network restrictions
- **PostgreSQL Flexible Server**: Database with private network access only
- **Storage Account**: Secure blob storage with private endpoints
- **Monitoring**: Comprehensive logging and alerting with Log Analytics and Application Insights

## Security Features

### Network Security
- Private subnets with Network Security Groups (NSGs)
- Private DNS zones for service resolution
- Private endpoints for all PaaS services
- No public internet access to databases or storage

### Key Vault Security
- RBAC authorization enabled
- Network access restrictions
- Purge protection enabled
- Secure secret storage for credentials

### Database Security
- Private network access only
- No firewall rules allowing public internet
- Enhanced logging and monitoring
- Encrypted at rest and in transit

### Storage Security
- Private endpoints only
- No public blob access
- Advanced Threat Protection enabled
- Lifecycle management policies
- Comprehensive audit logging

### Monitoring & Alerting
- Centralized logging with Log Analytics
- Security event monitoring
- Automated alerting for anomalies
- Performance monitoring with Application Insights

## Prerequisites

1. **Azure CLI** - [Install Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
2. **Terraform** - [Install Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
3. **Azure Subscription** with appropriate permissions

## Required Azure Permissions

Your Azure service principal or user account needs:
- `Contributor` role on the subscription or resource group
- `User Access Administrator` role for RBAC assignments
- `Key Vault Administrator` role for Key Vault management

## Quick Start

1. **Clone and Configure**
   ```bash
   # Copy the example variables file
   cp terraform.tfvars.example terraform.tfvars

   # Edit terraform.tfvars with your values
   nano terraform.tfvars
   ```

2. **Initialize Terraform**
   ```bash
   terraform init
   ```

3. **Plan Deployment**
   ```bash
   terraform plan
   ```

4. **Deploy Infrastructure**
   ```bash
   terraform apply
   ```

## Configuration Options

### Environment Variables
Key configuration options in `terraform.tfvars`:

- `environment`: Environment name (dev/staging/prod)
- `location`: Azure region
- `project_name`: Project identifier for resource naming
- `allowed_ip_addresses`: Your IP addresses for emergency access

### Customization
- **Production**: Set `environment = "prod"` for enhanced features (HA PostgreSQL, longer retention)
- **Development**: Use default settings for cost-effective development environments

## Security Considerations

### Network Access
- All resources are isolated in private subnets
- Private endpoints provide secure connectivity
- NSGs control traffic flow between subnets

### Emergency Access
- Add your IP addresses to `allowed_ip_addresses` for emergency management access
- Consider using Azure Bastion for secure administrative access

### Secrets Management
- Database passwords are auto-generated and stored in Key Vault
- Application secrets should be stored in Key Vault, not in code
- Use managed identities for service-to-service authentication

## Monitoring & Alerts

The infrastructure includes comprehensive monitoring:

### Log Analytics Workspace
- Centralizes logs from all resources
- 30-day retention for dev, 90-day for production

### Security Alerts
- Key Vault access failures
- Storage account unusual access patterns
- Failed authentication attempts

### Operational Alerts
- Database connection issues
- High CPU usage
- Storage transaction volume spikes

### Customization
Update email addresses in `monitoring.tf`:
```hcl
email_receiver {
  name          = "your-team"
  email_address = "alerts@yourcompany.com"
}
```

## Cost Optimization

### Development Environment
- Uses basic SKUs for cost efficiency
- Shorter retention periods
- Single-region deployment

### Production Considerations
- Enable geo-redundant backup for PostgreSQL
- Use Premium storage for better performance
- Consider reserved instances for cost savings

## Maintenance

### Regular Tasks
1. **Review Access**: Regularly audit Key Vault access policies
2. **Update Firewall Rules**: Remove obsolete IP addresses
3. **Monitor Costs**: Review Azure Cost Management reports
4. **Security Updates**: Keep Terraform providers updated

### Backup Strategy
- PostgreSQL: Automated backups with 35-day retention
- Storage: Versioning and soft delete enabled
- Key Vault: Backup secrets to separate Key Vault in different region

## Troubleshooting

### Common Issues

**Terraform State Lock**
```bash
terraform force-unlock <lock-id>
```

**Permission Denied**
- Verify service principal has correct roles
- Check Key Vault access policies
- Ensure network connectivity for private endpoints

**DNS Resolution Issues**
- Verify private DNS zone configuration
- Check virtual network links
- Test connectivity from within the VNet

## Contributing

1. Follow Terraform best practices
2. Update documentation for new features
3. Test changes in development environment first
4. Use semantic versioning for releases

## Security Compliance

This configuration addresses common compliance requirements:
- **SOC 2**: Network segmentation, access controls, monitoring
- **ISO 27001**: Security controls, incident response, audit logging
- **GDPR**: Data encryption, access controls, audit trails
- **HIPAA**: Network isolation, encryption at rest/transit, logging

For specific compliance requirements, additional configurations may be needed.

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review Azure documentation
3. Submit issues to the project repository
4. Contact your platform engineering team