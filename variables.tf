# ----------------------------------------
# General Configuration
# ----------------------------------------

variable "suffix" {
  description = "Optional suffix for resource names."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}

# ----------------------------------------
# ECS Cluster Configuration
# ----------------------------------------

variable "cluster_name" {
  description = "Name of the ECS cluster."
  type        = string
}

variable "cluster_settings" {
  description = "List of cluster settings configurations."
  type        = list(any)
  default     = []
}

variable "capacity_providers" {
  description = "Map of Fargate capacity providers with required strategy settings."
  type = map(object({
    default_capacity_provider_strategy = object({
      weight = number
      base   = optional(number, 0)
    })
  }))

  validation {
    condition = length([
      for provider, config in var.capacity_providers :
      provider if lookup(config.default_capacity_provider_strategy, "base", 0) > 0
    ]) <= 1
    error_message = "Only one capacity provider can have a 'base' value greater than 0."
  }

  default = {
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
}

variable "service_connect_defaults" {
  description = "Default Service Connect configuration for the ECS cluster."
  type = object({
    namespace = string
  })
  default = null
}

# ----------------------------------------
# Logging Configuration
# ----------------------------------------

variable "create_cloudwatch_log_group" {
  description = "Enable or disable the creation of a CloudWatch Log Group for ECS logs."
  type        = bool
  default     = false
}

variable "cloudwatch_log_group_retention_days" {
  description = "The number of days to retain logs for the cluster."
  type        = number
  default     = 30

  validation {
    condition     = var.cloudwatch_log_group_retention_days >= 1 && var.cloudwatch_log_group_retention_days <= 3650
    error_message = "Log retention days must be between 1 and 3650."
  }
}

variable "create_s3_logging_bucket" {
  description = "Enable or disable the creation of an S3 bucket for ECS logs."
  type        = bool
  default     = false
}

variable "s3_key_prefix" {
  description = "Prefix for logs stored in the S3 bucket."
  type        = string
  default     = "logs/"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_/.]*$", var.s3_key_prefix))
    error_message = "S3 key prefix must only contain alphanumeric characters, dashes, underscores, slashes, or dots."
  }
}

# ----------------------------------------
# VPC Configuration
# ----------------------------------------

variable "vpc" {
  description = "VPC configuration settings."
  type = object({
    id = string
    private_subnets = list(object({
      id   = string
      cidr = string
    }))
    public_subnets = list(object({
      id   = string
      cidr = string
    }))
  })

  validation {
    condition     = can(regex("^vpc-[a-f0-9]+$", var.vpc.id))
    error_message = "The VPC ID must be in the format 'vpc-xxxxxxxxxxxxxxxxx'."
  }

  validation {
    condition     = length(var.vpc.private_subnets) > 0
    error_message = "At least one private subnet must be defined."
  }

  validation {
    condition     = alltrue([for subnet in var.vpc.private_subnets : can(regex("^subnet-[a-f0-9]+$", subnet.id))])
    error_message = "Each private subnet must have a valid subnet ID (e.g., 'subnet-xxxxxxxxxxxxxxxxx')."
  }

  validation {
    condition     = alltrue([for subnet in var.vpc.private_subnets : can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}/\\d{1,2}$", subnet.cidr))])
    error_message = "Each subnet must have a valid CIDR block (e.g., '10.0.1.0/24')."
  }

  validation {
    condition     = alltrue([for subnet in var.vpc.public_subnets : can(regex("^subnet-[a-f0-9]+$", subnet.id))])
    error_message = "Each private subnet must have a valid subnet ID (e.g., 'subnet-xxxxxxxxxxxxxxxxx')."
  }

  validation {
    condition     = alltrue([for subnet in var.vpc.public_subnets : can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}/\\d{1,2}$", subnet.cidr))])
    error_message = "Each subnet must have a valid CIDR block (e.g., '10.0.1.0/24')."
  }
}

variable "ecs_services" {
  description = "List of ECS services to be created"
  type = list(object({
    name                  = string
    desired_count         = optional(number, 1)
    cpu                   = optional(string, "256")
    memory                = optional(string, "512")
    container_definitions = string

    execution_role_policies            = optional(list(string), [])
    enable_execute_command             = optional(bool, false)
    force_new_deployment               = optional(bool, false)
    deployment_minimum_healthy_percent = optional(number, 100)
    deployment_maximum_percent         = optional(number, 200)

    subnet_ids       = list(string)
    security_groups  = list(string)
    assign_public_ip = optional(bool, false)

    enable_alb         = optional(bool, false)
    enable_https       = optional(bool, false)
    allowed_http_cidrs = optional(list(string), ["0.0.0.0/0"])
    enable_autoscaling = optional(bool, false)

    # Service Discovery Configuration (mutually exclusive - choose one)
    enable_private_service_discovery = optional(bool, false) # Enable private DNS namespace for internal service-to-service communication
    enable_public_service_discovery  = optional(bool, false) # Enable public DNS namespace for external service discovery with health checks
    health_check_path                = optional(string, "/") # Health check path for public service discovery Route 53 health checks

    # Legacy service discovery configuration (for backward compatibility)
    enable_service_discovery = optional(bool, false) # Enable service discovery (legacy)
    service_discovery_config = optional(object({
      namespace_id = optional(string)
      service_name = string
      dns_config = object({
        ttl            = number
        type           = string
        routing_policy = string
      })
    }))

    enable_ecs_managed_tags = optional(bool, false)
    propagate_tags          = optional(string, "TASK_DEFINITION")
    service_tags            = optional(map(string))
    task_tags               = optional(map(string))
  }))

  default = []

  validation {
    condition     = alltrue([for s in var.ecs_services : contains(["TASK_DEFINITION", "SERVICE", "NONE"], s.propagate_tags)])
    error_message = "propagate_tags must be one of: TASK_DEFINITION, SERVICE, or NONE."
  }

  validation {
    condition = alltrue([
      for s in var.ecs_services : can(regex("^(256|512|1024|2048|4096|8192|16384)$", s.cpu))
    ])
    error_message = "cpu must be a valid numeric string: 256, 512, 1024, 2048, 4096, 8192, or 16384."
  }

  validation {
    condition = alltrue([
      for s in var.ecs_services : can(regex("^(512|1024|2048|3072|4096|5120|6144|7168|8192|9216|10240|11264|12288|13312|14336|15360|16384)$", s.memory))
    ])
    error_message = "memory must be a valid numeric string: 512, 1024, 2048, ..., 16384 (multiples of 512)."
  }

  validation {
    condition     = alltrue([for s in var.ecs_services : s.desired_count >= 0])
    error_message = "desired_count must be greater than or equal to 0."
  }

  validation {
    condition     = alltrue([for s in var.ecs_services : s.deployment_minimum_healthy_percent >= 0 && s.deployment_minimum_healthy_percent <= 200])
    error_message = "deployment_minimum_healthy_percent must be between 0 and 200."
  }

  validation {
    condition     = alltrue([for s in var.ecs_services : s.deployment_maximum_percent >= 0 && s.deployment_maximum_percent <= 200])
    error_message = "deployment_maximum_percent must be between 0 and 200."
  }

  validation {
    condition     = alltrue([for s in var.ecs_services : length(s.subnet_ids) > 0])
    error_message = "Each service must have at least one subnet ID."
  }

  validation {
    condition     = alltrue([for s in var.ecs_services : length(s.security_groups) > 0])
    error_message = "Each service must have at least one security group."
  }

  validation {
    condition     = alltrue([for s in var.ecs_services : s.enable_https == false])
    error_message = "HTTPS is not supported. Set enable_https to false."
  }

  validation {
    condition = alltrue([
      for s in var.ecs_services : !(s.enable_private_service_discovery && s.enable_public_service_discovery)
    ])
    error_message = "A service cannot enable both private and public service discovery simultaneously. Choose one: enable_private_service_discovery OR enable_public_service_discovery."
  }

  validation {
    condition = alltrue([
      for s in var.ecs_services : !(s.enable_service_discovery && (s.enable_private_service_discovery || s.enable_public_service_discovery))
    ])
    error_message = "Legacy enable_service_discovery cannot be used with the new service discovery configuration. Use enable_private_service_discovery or enable_public_service_discovery instead."
  }

  validation {
    condition = alltrue([
      for s in var.ecs_services : s.enable_service_discovery == false || s.service_discovery_config != null
    ])
    error_message = "service_discovery_config must be provided when enable_service_discovery is true."
  }
}

# ----------------------------------------
# ECS Service Auto Scaling Configuration
# ----------------------------------------

variable "ecs_autoscaling" {
  description = "List of ECS service auto scaling configurations"
  type = list(object({
    service_name       = string
    min_capacity       = number
    max_capacity       = number
    scalable_dimension = string
    policy_name        = string
    policy_type        = string
    target_value       = number

    predefined_metric_type = optional(string)
    custom_metric = optional(object({
      metric_name = string
      namespace   = string
      statistic   = string
      dimensions = optional(list(object({
        name  = string
        value = string
      })), [])
    }))
  }))

  default = []

  validation {
    condition = alltrue([
      for s in var.ecs_autoscaling :
      (s.predefined_metric_type != null) || (s.custom_metric != null)
    ])
    error_message = "At least one of predefined_metric_type or custom_metric must be defined."
  }

  validation {
    condition = alltrue([
      for s in var.ecs_autoscaling :
      s.predefined_metric_type == null || contains(["ECSServiceAverageCPUUtilization", "ECSServiceAverageMemoryUtilization"], s.predefined_metric_type)
    ])
    error_message = "Valid predefined_metric_type values are ECSServiceAverageCPUUtilization or ECSServiceAverageMemoryUtilization."
  }

  validation {
    condition = alltrue([
      for s in var.ecs_autoscaling : s.min_capacity >= 0
    ])
    error_message = "min_capacity must be greater than or equal to 0."
  }

  validation {
    condition = alltrue([
      for s in var.ecs_autoscaling : s.max_capacity >= s.min_capacity
    ])
    error_message = "max_capacity must be greater than or equal to min_capacity."
  }

  validation {
    condition = alltrue([
      for s in var.ecs_autoscaling : s.target_value > 0 && s.target_value <= 100
    ])
    error_message = "target_value must be between 1 and 100 (percentage-based scaling)."
  }

  validation {
    condition = alltrue([
      for s in var.ecs_autoscaling : contains(["TargetTrackingScaling", "StepScaling"], s.policy_type)
    ])
    error_message = "Valid policy_type values are TargetTrackingScaling or StepScaling."
  }

  validation {
    condition = alltrue([
      for s in var.ecs_autoscaling : contains(["ecs:service:DesiredCount"], s.scalable_dimension)
    ])
    error_message = "Only 'ecs:service:DesiredCount' is allowed as a scalable_dimension for ECS services."
  }
}
