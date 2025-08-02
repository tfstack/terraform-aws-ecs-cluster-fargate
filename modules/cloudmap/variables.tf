variable "create_namespace" {
  description = "Whether to create an HTTP namespace"
  type        = bool
  default     = false
}

variable "create_private_dns_namespace" {
  description = "Whether to create a private DNS namespace"
  type        = bool
  default     = false
}

variable "create_public_dns_namespace" {
  description = "Whether to create a public DNS namespace"
  type        = bool
  default     = false
}

variable "create_ecs_service_discovery_role" {
  description = "Whether to create IAM role for ECS service discovery"
  type        = bool
  default     = false
}

variable "namespace_name" {
  description = "Name of the CloudMap namespace"
  type        = string
  default     = null
}

variable "namespace_description" {
  description = "Description of the CloudMap namespace"
  type        = string
  default     = null
}

variable "existing_namespace_id" {
  description = "ID of an existing namespace to use"
  type        = string
  default     = null
}

variable "vpc_id" {
  description = "VPC ID for private DNS namespace"
  type        = string
  default     = null
}

variable "services" {
  description = "Map of CloudMap services to create"
  type = map(object({
    name            = string
    description     = optional(string)
    dns_ttl         = optional(number, 10)
    dns_record_type = optional(string, "A")
    routing_policy  = optional(string, "MULTIVALUE")
    health_check_config = optional(object({
      resource_path     = string
      type              = string
      failure_threshold = optional(number, 3)
    }))
    health_check_custom_config            = optional(bool, false)
    custom_health_check_failure_threshold = optional(number, 1)
    tags                                  = optional(map(string), {})
  }))
  default = {}
}

variable "dns_ttl" {
  description = "TTL for DNS records"
  type        = number
  default     = 10
}

variable "dns_record_type" {
  description = "Type of DNS record"
  type        = string
  default     = "A"
  validation {
    condition     = contains(["A", "AAAA", "CNAME", "SRV"], var.dns_record_type)
    error_message = "DNS record type must be one of: A, AAAA, CNAME, SRV."
  }
}

variable "routing_policy" {
  description = "Routing policy for the service"
  type        = string
  default     = "MULTIVALUE"
  validation {
    condition     = contains(["MULTIVALUE", "WEIGHTED"], var.routing_policy)
    error_message = "Routing policy must be one of: MULTIVALUE, WEIGHTED."
  }
}

variable "enable_health_checks" {
  description = "Enable health checks for the service. Set to false when using private IPs or unsupported instance types."
  type        = bool
  default     = true
}

# Add validation to ensure proper health check configuration
locals {
  validation_errors = flatten([
    for service_name, service in var.services : [
      # Validate that health_check_config is only used with public DNS namespaces
      service.health_check_config != null && !var.create_public_dns_namespace ?
      "Service '${service_name}': health_check_config can only be used with public DNS namespaces" : null,

      # Validate that health_check_custom_config is only used with private DNS namespaces
      service.health_check_custom_config && !var.create_private_dns_namespace ?
      "Service '${service_name}': health_check_custom_config can only be used with private DNS namespaces" : null,

      # Validate that both health check types are not enabled simultaneously
      service.health_check_config != null && service.health_check_custom_config ?
      "Service '${service_name}': Cannot use both health_check_config and health_check_custom_config simultaneously" : null
    ]
  ])
}

# Validation check to enforce health check configuration rules
check "health_check_validation" {
  assert {
    condition     = length(compact(local.validation_errors)) == 0
    error_message = "Health check configuration errors:\n${join("\n", compact(local.validation_errors))}"
  }
}

variable "enable_dns_config" {
  description = "Enable DNS configuration for the service. Set to false for HTTP namespaces or when using existing HTTP namespaces."
  type        = bool
  default     = true
}

variable "tags" {
  description = "A map of tags to assign to the resources"
  type        = map(string)
  default     = {}
}
