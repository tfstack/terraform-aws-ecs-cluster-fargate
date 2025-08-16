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

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
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

  suffix = random_string.suffix.result

  tags = {
    Environment = "dev"
    Project     = "example"
  }
}

############################################
# VPC Configuration
############################################

module "vpc" {
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

# Security Group for ALB
resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "Security group for Application Load Balancer"
  vpc_id      = module.vpc.vpc_id

  # Allow inbound HTTP traffic from internet
  ingress {
    description = "HTTP from internet"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-alb"
  }
}

############################################
# ECS Cluster Configuration
############################################

module "ecs_cluster_fargate" {
  source = "../.."

  # Core Configuration
  cluster_name = local.name
  suffix       = local.suffix

  # VPC Configuration
  vpc = {
    id = module.vpc.vpc_id
    private_subnets = [
      for i, subnet in module.vpc.private_subnet_ids :
      { id = subnet, cidr = module.vpc.private_subnet_cidrs[i] }
    ]
    public_subnets = [
      for i, subnet in module.vpc.public_subnet_ids :
      { id = subnet, cidr = module.vpc.public_subnet_cidrs[i] }
    ]
  }
  # Cluster Settings
  cluster_settings = [
    { name = "containerInsights", value = "enabled" }
  ]

  # Logging Configuration
  s3_key_prefix                       = "logs/"
  create_cloudwatch_log_group         = true
  cloudwatch_log_group_retention_days = 90
  create_s3_logging_bucket            = true

  # Capacity Providers
  capacity_providers = {
    FARGATE = {
      default_capacity_provider_strategy = {
        weight = 50
        base   = 20
      }
    }
    FARGATE_SPOT = {
      default_capacity_provider_strategy = {
        weight = 50
      }
    }
  }

  ecs_services = [
    {
      name                 = "hello-webapp"
      desired_count        = 3
      cpu                  = "256"
      memory               = "512"
      force_new_deployment = true

      execution_role_policies = [
        "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
        "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
      ]

      container_definitions = jsonencode([
        {
          name      = "hello-webapp"
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
              "curl -f http://localhost:8080/health || exit 1"
            ]
            interval    = 30
            timeout     = 5
            retries     = 3
            startPeriod = 60
          }
          logConfiguration = {
            logDriver = "awslogs"
            options = {
              awslogs-group         = "/aws/ecs/${local.name}-hello-webapp"
              awslogs-region        = data.aws_region.current.region
              awslogs-stream-prefix = "${local.name}-hello-webapp"
            }
          }
        }
      ])

      deployment_minimum_healthy_percent = 100
      deployment_maximum_percent         = 200
      health_check_grace_period_seconds  = 30

      subnet_ids       = module.vpc.private_subnet_ids
      security_groups  = [aws_security_group.alb.id]
      assign_public_ip = false

      # ALB Configuration
      enable_alb              = true
      enable_internal_alb     = false         # Set to true for internal (private) ALB, false for internet-facing ALB
      allowed_http_cidrs      = ["0.0.0.0/0"] # Allow HTTP access from anywhere
      enable_ecs_managed_tags = true
      propagate_tags          = "TASK_DEFINITION"

      service_tags = {
        Environment = "dev"
        Project     = "hello-webapp"
        Owner       = "devops"
      }

      task_tags = {
        TaskType = "frontend"
        Version  = "1.0"
      }
    }
  ]

  ecs_autoscaling = [
    {
      service_name           = "${local.name}-hello-webapp"
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

output "alb_http_url" {
  description = "HTTP URL for the ALB on port 8080"
  value       = "http://${module.ecs_cluster_fargate.alb_dns_names["hello-webapp"]}:8080"
}
