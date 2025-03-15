terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Generate a random string as suffix
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data Sources
data "aws_availability_zones" "available" {}

data "aws_ami" "ecs_optimized" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
}

# Local Variables
locals {
  name                 = "cltest"
  base_name            = "${local.name}-${random_string.suffix.result}"
  app_name             = "web-app"
  region               = "ap-southeast-1"
  vpc_cidr             = "10.0.0.0/16"
  enable_dns_hostnames = true

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  tags = {
    Environment = "test"
    Project     = "example"
  }
}

# VPC Module
module "vpc" {
  source = "tfstack/vpc/aws"

  vpc_name           = local.base_name
  vpc_cidr           = local.vpc_cidr
  availability_zones = local.azs

  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets

  eic_subnet = "none"

  jumphost_instance_create     = false
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
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
    description = "allow all incoming traffic"
    self        = false
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "allow all outbound traffic"
  }

  tags = {
    Name = "${local.name}-ecs"
  }
}

# Outputs
output "suffix" {
  value = random_string.suffix.result
}

output "region" {
  value = local.region
}

output "cluster_name" {
  value = local.name
}

output "app_name" {
  value = local.app_name
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnets" {
  value = module.vpc.private_subnet_ids
}

output "private_subnets_cidr_blocks" {
  value = module.vpc.private_subnet_cidrs
}

output "public_subnets" {
  value = module.vpc.public_subnet_ids
}

output "public_subnets_cidr_blocks" {
  value = module.vpc.public_subnet_cidrs
}

output "security_group_id" {
  value = aws_security_group.ecs.id
}

output "tags" {
  value = local.tags
}
