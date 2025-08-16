############################################
# Provider Configuration
############################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-2"
}

############################################
# Data Sources
############################################

data "aws_region" "current" {}

data "http" "my_public_ip" {
  url = "https://checkip.amazonaws.com/"
}

############################################
# Local Variables
############################################

locals {
  azs             = ["ap-southeast-2a", "ap-southeast-2b", "ap-southeast-2c"]
  name            = "example"
  private_subnets = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  region          = "ap-southeast-2"
  vpc_cidr        = "10.0.0.0/16"
  web_access_cidr = "${trimspace(data.http.my_public_ip.response_body)}/32"
  tags = {
    Environment = "dev"
    Project     = "example"
  }

  # Service port mapping
  service_ports = {
    "web2"   = 80
    "web1"   = 8080
    "pinger" = null # No port needed for test service
  }
}

############################################
# VPC Configuration
############################################

module "aws_vpc" {
  source = "cloudbuildlab/vpc/aws"

  vpc_name           = local.name
  vpc_cidr           = local.vpc_cidr
  availability_zones = local.azs

  public_subnet_cidrs  = local.public_subnets
  private_subnet_cidrs = local.private_subnets

  # Enable Internet Gateway & NAT Gateway
  # A single NAT gateway is used instead of multiple for cost efficiency.
  create_igw       = true
  nat_gateway_type = "single"

  tags = local.tags
}

############################################################
# Jumphost
############################################################

module "jumphost" {
  source = "tfstack/jumphost/aws"

  name      = "${local.name}-jumphost"
  ami_type  = "amazonlinux2"
  subnet_id = module.aws_vpc.private_subnet_ids[0]
  vpc_id    = module.aws_vpc.vpc_id

  create_security_group = true
  allowed_cidr_blocks   = [local.web_access_cidr]
  assign_eip            = false

  user_data_extra = <<-EOT
    yum install -y mtr nc
  EOT

  tags = local.tags
}

# ############################################
# # Security Groups
# ############################################

# Security group for web2
resource "aws_security_group" "web2" {
  name        = "${local.name}-web2"
  description = "Security group for web2 - allows ALB health checks and HTTP traffic"
  vpc_id      = module.aws_vpc.vpc_id

  # Allow inbound HTTP traffic from ALB on port 80 (nginx default)
  ingress {
    description = "HTTP from ALB for web2 health checks and web traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow ALB health checks and web2 web traffic
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name}-web2" })
}

# Security group for the web1
resource "aws_security_group" "web1" {
  name        = "${local.name}-web1"
  description = "Security group for web1 - allows ALB health checks and traffic"
  vpc_id      = module.aws_vpc.vpc_id

  # Allow inbound HTTP traffic from ALB on port 8080
  ingress {
    description = "HTTP from ALB for web1 health checks and traffic"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow ALB health checks and traffic
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name}-web1" })
}

# Security group for the pinger
resource "aws_security_group" "pinger" {
  name        = "${local.name}-pinger"
  description = "Security group for pinger - allows outbound to other services"
  vpc_id      = module.aws_vpc.vpc_id

  # Allow all outbound traffic to reach other services
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name}-pinger" })
}

# ############################################
# # ECS Cluster Configuration
# ############################################

# ECS Cluster Configuration with External Cloud Map Integration
module "ecs_cluster_fargate" {
  source = "../.."

  # Core Configuration
  cluster_name = local.name
  suffix       = ""

  # VPC Configuration
  vpc = {
    id = module.aws_vpc.vpc_id
    private_subnets = [
      for i, subnet in module.aws_vpc.private_subnet_ids :
      { id = subnet, cidr = module.aws_vpc.private_subnet_cidrs[i] }
    ]
    public_subnets = [
      for i, subnet in module.aws_vpc.public_subnet_ids :
      { id = subnet, cidr = module.aws_vpc.public_subnet_cidrs[i] }
    ]
  }

  # Cluster Settings
  cluster_settings = [
    { name = "containerInsights", value = "enabled" }
  ]

  # Logging Configuration
  create_cloudwatch_log_group         = true
  cloudwatch_log_group_retention_days = 30

  # Capacity Providers
  capacity_providers = {
    FARGATE = {
      default_capacity_provider_strategy = {
        weight = 100
        base   = 0
      }
    }
  }

  ecs_services = [
    {
      name                 = "web2"
      desired_count        = 1
      cpu                  = "256"
      memory               = "512"
      force_new_deployment = true

      execution_role_policies = [
        "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
      ]

      container_definitions = jsonencode([
        {
          name      = "web2"
          image     = "nginx:latest"
          cpu       = 256
          memory    = 512
          essential = true
          portMappings = [{
            containerPort = 80
          }]
          healthCheck = {
            command     = ["CMD-SHELL", "curl -f http://127.0.0.1/ || exit 1"]
            interval    = 30
            timeout     = 10
            retries     = 5
            startPeriod = 30
          }
          logConfiguration = {
            logDriver = "awslogs"
            options = {
              awslogs-group         = "/aws/ecs/${local.name}-web2"
              awslogs-region        = data.aws_region.current.region
              awslogs-stream-prefix = "${local.name}-web2"
            }
          }
        }
      ])

      deployment_minimum_healthy_percent = 100
      deployment_maximum_percent         = 200
      health_check_grace_period_seconds  = 30

      subnet_ids       = module.aws_vpc.private_subnet_ids
      security_groups  = [aws_security_group.web2.id]
      assign_public_ip = false

      enable_alb                       = true
      allowed_http_cidrs               = [local.web_access_cidr] # Restrict to your IP only
      enable_autoscaling               = true
      enable_private_service_discovery = true # Use private for internal service-to-service communication
      service_discovery_container_name = "web2"
      enable_ecs_managed_tags          = true
      propagate_tags                   = "TASK_DEFINITION"

      service_tags = {
        Environment = "dev"
        Project     = "web2"
        Owner       = "devops"
      }

      task_tags = {
        TaskType = "web-app"
        Version  = "1.0"
      }
    },
    {
      name                 = "web1"
      desired_count        = 1
      cpu                  = "256"
      memory               = "512"
      force_new_deployment = true

      execution_role_policies = [
        "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
      ]

      container_definitions = jsonencode([
        {
          name      = "web1"
          image     = "ghcr.io/platformfuzz/go-hello-service:latest"
          cpu       = 256
          memory    = 512
          essential = true
          portMappings = [{
            containerPort = 8080
          }]
          healthCheck = {
            command = [
              "CMD-SHELL",
              "wget --quiet --tries=1 --spider http://localhost:8080/health || exit 1"
            ]
            interval    = 30
            timeout     = 5
            retries     = 3
            startPeriod = 10
          }
          logConfiguration = {
            logDriver = "awslogs"
            options = {
              awslogs-group         = "/aws/ecs/${local.name}-web1"
              awslogs-region        = data.aws_region.current.region
              awslogs-stream-prefix = "${local.name}-web1"
            }
          }
        }
      ])

      deployment_minimum_healthy_percent = 100
      deployment_maximum_percent         = 200
      health_check_grace_period_seconds  = 30

      subnet_ids       = module.aws_vpc.private_subnet_ids
      security_groups  = [aws_security_group.web1.id] # Go service on port 8080
      assign_public_ip = false

      enable_alb                       = true
      allowed_http_cidrs               = [local.web_access_cidr] # Restrict to your IP only
      enable_autoscaling               = true
      enable_private_service_discovery = true # Use private for internal service-to-service communication
      service_discovery_container_name = "web1"
      enable_ecs_managed_tags          = true
      health_check_path                = "/health" # Go app health endpoint
      propagate_tags                   = "TASK_DEFINITION"

      service_tags = {
        Environment = "dev"
        Project     = "web1"
        Owner       = "devops"
      }

      task_tags = {
        TaskType = "frontend"
        Version  = "1.0"
      }
    },
    {
      name                 = "pinger"
      desired_count        = 1
      cpu                  = "256"
      memory               = "512"
      force_new_deployment = true

      execution_role_policies = [
        "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
      ]

      container_definitions = jsonencode([
        {
          name      = "pinger"
          image     = "curlimages/curl:latest"
          cpu       = 256
          memory    = 512
          essential = true
          healthCheck = {
            command     = ["CMD-SHELL", "echo 'pinger is healthy'"]
            interval    = 30
            timeout     = 5
            retries     = 3
            startPeriod = 10
          }
          command = [
            "sh",
            "-c",
            <<-EOT
              while true; do
                echo 'Testing service discovery...'
                curl -s -f http://web2.internal.${local.name}.local:80 > /dev/null && echo 'http://web2.internal.${local.name}.local:80 = ok' || echo 'http://web2.internal.${local.name}.local:80 = fail'
                curl -s -f http://web1.internal.${local.name}.local:8080 > /dev/null && echo 'http://web1.internal.${local.name}.local:8080 = ok' || echo 'http://web1.internal.${local.name}.local:8080 = fail'
                echo 'Sleeping for 30 seconds...'
                sleep 30
              done
            EOT
          ]
          logConfiguration = {
            logDriver = "awslogs"
            options = {
              awslogs-group         = "/aws/ecs/${local.name}-pinger"
              awslogs-region        = data.aws_region.current.region
              awslogs-stream-prefix = "${local.name}-pinger"
            }
          }
        }
      ])

      deployment_minimum_healthy_percent = 100
      deployment_maximum_percent         = 200
      health_check_grace_period_seconds  = 30

      subnet_ids       = module.aws_vpc.private_subnet_ids
      security_groups  = [aws_security_group.pinger.id]
      assign_public_ip = false

      enable_alb                       = false # No ALB needed for test service
      enable_autoscaling               = false # No autoscaling for test service
      enable_private_service_discovery = true
      service_discovery_container_name = "pinger"
      enable_ecs_managed_tags          = true
      propagate_tags                   = "TASK_DEFINITION"

      service_tags = {
        Environment = "dev"
        Project     = "pinger"
        Owner       = "devops"
      }

      task_tags = {
        TaskType = "test"
        Version  = "1.0"
      }
    }
  ]

  ecs_autoscaling = [
    {
      service_name           = "${local.name}-web2"
      min_capacity           = 3
      max_capacity           = 6
      scalable_dimension     = "ecs:service:DesiredCount"
      policy_name            = "scale-on-cpu"
      policy_type            = "TargetTrackingScaling"
      target_value           = 80
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    },
    {
      service_name           = "${local.name}-web1"
      min_capacity           = 3
      max_capacity           = 6
      scalable_dimension     = "ecs:service:DesiredCount"
      policy_name            = "scale-on-cpu"
      policy_type            = "TargetTrackingScaling"
      target_value           = 80
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  ]

  tags = local.tags
}

############################################
# Outputs
############################################

output "vpc_id" {
  description = "VPC ID"
  value       = module.aws_vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.aws_vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.aws_vpc.public_subnet_ids
}

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = local.name
}

output "cluster_id" {
  description = "ID of the ECS cluster"
  value       = module.ecs_cluster_fargate.ecs_cluster_id
}

output "ecs_services" {
  description = "ECS service names and their configurations"
  value = {
    for service_name, service_config in module.ecs_cluster_fargate.ecs_services :
    service_name => {
      service_name = service_name
      arn          = service_config.arn
    }
  }
}

output "load_balancer_dns" {
  description = "DNS names of all load balancers"
  value       = module.ecs_cluster_fargate.alb_dns_names
}

output "load_balancer_urls" {
  description = "URLs to access all services with ports"
  value = {
    for service_name, dns_name in module.ecs_cluster_fargate.alb_dns_names :
    service_name => "http://${dns_name}:${local.service_ports[service_name]}"
  }
}

output "service_discovery_namespace" {
  description = "Service discovery namespace"
  value       = module.ecs_cluster_fargate.service_discovery_namespace_id
}

output "service_discovery_services" {
  description = "Service discovery services"
  value       = module.ecs_cluster_fargate.service_discovery_services
}

output "public_service_discovery_namespace" {
  description = "Public service discovery namespace"
  value       = module.ecs_cluster_fargate.public_service_discovery_namespace_name
}

output "public_service_discovery_services" {
  description = "Public service discovery services"
  value       = module.ecs_cluster_fargate.public_service_discovery_services
}

output "private_service_discovery_arns" {
  description = "Map of ECS service names to their private Cloud Map service ARNs for use in ECS serviceRegistries"
  value       = module.ecs_cluster_fargate.service_discovery_service_arns
}
