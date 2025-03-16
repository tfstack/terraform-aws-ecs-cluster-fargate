############################################
# Provider Configuration
############################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.84.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

############################################
# Random Suffix for Resource Names
############################################

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

############################################
# Data Sources
############################################

data "aws_region" "current" {}
data "aws_availability_zones" "available" {}

data "http" "my_public_ip" {
  url = "http://ifconfig.me/ip"
}

############################################
# Local Variables
############################################

locals {
  name      = "cltest"
  base_name = "${local.name}-${random_string.suffix.result}"

  tags = {
    Environment = "dev"
    Project     = "example"
  }
}

############################################
# VPC Configuration
############################################

module "vpc" {
  source = "tfstack/vpc/aws"

  vpc_name           = local.base_name
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 3)

  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  eic_subnet        = "none"
  eic_ingress_cidrs = ["${data.http.my_public_ip.response_body}/32"]

  jumphost_instance_create     = false
  jumphost_subnet              = "10.0.0.0/24"
  jumphost_log_prevent_destroy = false
  create_igw                   = true
  ngw_type                     = "single"

  tags = local.tags
}

# Security Group
resource "aws_security_group" "ecs" {
  name   = "${local.name}-ecs"
  vpc_id = module.vpc.vpc_id

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "allow all incoming traffic"
    from_port   = 0
    protocol    = -1
    self        = "false"
    to_port     = 0
  }

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "allow all outbound traffic"
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
  }

  tags = {
    Name = "${local.name}-ecs"
  }
}

############################################
# ECS Cluster Configuration
############################################

module "ecs_cluster_fargate" {
  source = "../.."

  # Core Configuration
  cluster_name = local.name
  suffix       = random_string.suffix.result

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
      name                 = "web-app"
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
          name      = "web-app"
          image     = "nginx:latest"
          cpu       = 256
          memory    = 512
          essential = true
          portMappings = [{
            containerPort = 80
          }]
          healthCheck = {
            command     = ["CMD-SHELL", "curl -f http://127.0.0.1 || exit 1"]
            interval    = 30
            timeout     = 5
            retries     = 3
            startPeriod = 10
          }
          logConfiguration = {
            logDriver = "awslogs"
            options = {
              awslogs-group         = "/aws/ecs/${local.name}-web-app"
              awslogs-region        = data.aws_region.current.name
              awslogs-stream-prefix = "${local.name}-nginx"
            }
          }
        }
      ])

      deployment_minimum_healthy_percent = 100
      deployment_maximum_percent         = 200
      health_check_grace_period_seconds  = 30

      subnet_ids       = module.vpc.private_subnet_ids
      security_groups  = [aws_security_group.ecs.id]
      assign_public_ip = false

      enable_alb              = true
      enable_ecs_managed_tags = true
      propagate_tags          = "TASK_DEFINITION"

      service_tags = {
        Environment = "staging"
        Project     = "WebApp"
        Owner       = "DevOps"
      }

      task_tags = {
        TaskType = "backend"
        Version  = "1.0"
      }
    }
  ]

  ecs_autoscaling = [
    {
      service_name           = "${local.name}-web-app"
      min_capacity           = 3
      max_capacity           = 12
      scalable_dimension     = "ecs:service:DesiredCount"
      policy_name            = "scale-on-cpu"
      policy_type            = "TargetTrackingScaling"
      target_value           = 75
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  ]

  tags = local.tags
}

# Outputs
output "all_module_outputs" {
  description = "All outputs from the ECS module"
  value       = module.ecs_cluster_fargate
}
