# Service Discovery with AWS Fargate and Cloud Map

This example demonstrates how to implement service discovery using AWS Cloud Map with ECS Fargate services. The example creates a microservices architecture where a frontend service communicates with a backend service using DNS-based service discovery.

## Architecture Overview

The example deploys the following architecture:

```plaintext
Internet
    │
    ▼
Application Load Balancer
    │
    ▼
Hello Service (Frontend)
    │
    ▼ (Service Discovery)
Name Service (Backend)
```

### Components

1. **VPC with Public and Private Subnets**: Provides network isolation
2. **ECS Fargate Cluster**: Hosts the containerized services
3. **AWS Cloud Map**: Provides service discovery functionality
4. **Application Load Balancer**: Routes external traffic to the hello service
5. **Hello Service**: Frontend service that calls the name service
6. **Name Service**: Backend service that generates random names

## Service Discovery Flow

1. **External Request**: Internet traffic arrives at the ALB
2. **ALB Routing**: ALB routes traffic to hello service instances
3. **Service Discovery**: Hello service uses DNS to discover name service instances
4. **Direct Communication**: Hello service communicates directly with name service instances
5. **Response**: Combined response is returned to the client

## Key Features

- **DNS-based Service Discovery**: Uses AWS Cloud Map for service registration and discovery
- **Private Communication**: Backend services communicate directly without going through load balancers
- **Load Balancing**: Client-side load balancing across service instances
- **Health Checks**: Automatic health monitoring and instance replacement
- **Security Groups**: Proper network isolation between services

## Prerequisites

- Terraform >= 1.0
- AWS CLI configured with appropriate permissions
- Access to AWS ECR public repositories

## Usage

### 1. Initialize Terraform

```bash
cd examples/service-discovery
terraform init
```

### 2. Review the Configuration

The example creates:

- A VPC with public and private subnets
- An ECS Fargate cluster
- AWS Cloud Map namespace and services
- Two ECS services with service discovery integration
- Application Load Balancer for external access
- Security groups for network isolation

### 3. Deploy the Infrastructure

```bash
# Validate the configuration
terraform validate

# Plan the deployment
terraform plan

# Apply the deployment
terraform apply
```

### 4. Test the Service Discovery

Once deployed, you can test the service discovery by:

1. **Access the Hello Service**: Use the load balancer URL from the outputs
2. **Verify Service Discovery**: Check that the hello service can reach the name service
3. **Test Load Balancing**: Multiple requests should show different backend instances

### 5. Clean Up

```bash
terraform destroy
```

## Configuration Details

### Service Discovery Setup

The example uses the module's built-in service discovery features:

```hcl
# Enable service discovery namespace creation
create_service_discovery_namespace = true
service_discovery_namespace = {
  name        = "internal"
  description = "Internal service discovery namespace for service discovery demo"
}
```

### Service Configuration with Service Discovery

Each service is configured with service discovery:

```hcl
{
  name = "name-service"
  # ... other configuration ...

  enable_service_discovery = true
  service_discovery_config = {
    namespace_id = null  # Will use the created namespace
    service_name = "name-service"
    dns_config = {
      ttl  = 10
      type = "A"
      routing_policy = "MULTIVALUE"
    }
  }
}
```

### Module Integration

The module automatically handles:

- Service discovery namespace creation
- Service registration with Cloud Map
- ECS service integration with service discovery
- DNS configuration and routing policies

### Environment Variables

The hello service is configured with the name service endpoint:

```hcl
environment = [
  {
    name  = "NAME_SERVER"
    value = "http://name-service.internal:80"
  }
]
```

## Security Considerations

### Network Security

- **Private Subnets**: Backend services run in private subnets
- **Security Groups**: Proper ingress/egress rules for service communication
- **No Public Access**: Backend services are not directly accessible from internet

### Service Communication

- **Internal DNS**: Services use internal DNS names for discovery
- **Direct Communication**: Peer-to-peer communication without load balancers
- **Health Monitoring**: Automatic health checks and instance replacement

## Monitoring and Troubleshooting

### CloudWatch Logs

All services log to CloudWatch with structured log groups:

- `/aws/ecs/{cluster-name}-name-service`
- `/aws/ecs/{cluster-name}-hello-service`

### Service Discovery Debugging

1. **Check Service Registration**: Verify services are registered in Cloud Map
2. **DNS Resolution**: Test DNS resolution from within the VPC
3. **Network Connectivity**: Verify security group rules allow communication

### Common Issues

1. **DNS Resolution Failures**: Check Cloud Map service registration
2. **Network Connectivity**: Verify security group configurations
3. **Health Check Failures**: Check container health check configurations

## Advanced Configuration

### Custom Images

To use custom container images:

1. Replace the `image` field in container definitions
2. Ensure ECR permissions are configured
3. Update health check commands if needed

### Scaling Configuration

The example includes basic scaling configurations. For production:

1. Add auto-scaling policies
2. Configure target tracking metrics
3. Set appropriate min/max capacity

### Service Mesh Integration

For more advanced service mesh features, consider:

1. AWS App Mesh integration
2. Envoy proxy sidecars
3. Advanced traffic routing rules

## Outputs

The example provides several useful outputs:

- `cluster_name`: ECS cluster name
- `cluster_id`: ECS cluster ID
- `load_balancer_url`: URL to access the hello service
- `service_discovery_endpoints`: Internal service discovery endpoints
- `vpc_id`: VPC ID for additional resources

## References

- [AWS Cloud Map Documentation](https://docs.aws.amazon.com/cloud-map/)
- [ECS Service Discovery](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-discovery.html)
- [Service Discovery Pattern](https://containersonaws.com/pattern/service-discovery-fargate-microservice-cloud-map)

## License

This example is provided under the same license as the parent module.
