output "namespace_id" {
  description = "ID of the created namespace"
  value       = local.namespace_id
}

output "namespace_arn" {
  description = "ARN of the created namespace"
  value = var.create_private_dns_namespace ? aws_service_discovery_private_dns_namespace.this[0].arn : (
    var.create_public_dns_namespace ? aws_service_discovery_public_dns_namespace.this[0].arn : (
      var.create_namespace ? aws_service_discovery_http_namespace.this[0].arn : null
    )
  )
}

output "namespace_name" {
  description = "Name of the created namespace"
  value = var.create_private_dns_namespace ? aws_service_discovery_private_dns_namespace.this[0].name : (
    var.create_public_dns_namespace ? aws_service_discovery_public_dns_namespace.this[0].name : (
      var.create_namespace ? aws_service_discovery_http_namespace.this[0].name : null
    )
  )
}

output "services" {
  description = "Map of created services with their details"
  value = {
    for k, v in aws_service_discovery_service.services : k => {
      id   = v.id
      arn  = v.arn
      name = v.name
    }
  }
}

output "service_arns" {
  description = "Map of service names to their ARNs for ECS integration"
  value = {
    for k, v in aws_service_discovery_service.services : k => v.arn
  }
}

output "ecs_service_discovery_role_arn" {
  description = "ARN of the ECS service discovery IAM role"
  value       = var.create_ecs_service_discovery_role && length(var.services) > 0 ? aws_iam_role.ecs_service_discovery[0].arn : null
}

output "ecs_service_discovery_role_name" {
  description = "Name of the ECS service discovery IAM role"
  value       = var.create_ecs_service_discovery_role && length(var.services) > 0 ? aws_iam_role.ecs_service_discovery[0].name : null
}

output "health_check_debug" {
  description = "Debug information for health check configuration - use for troubleshooting"
  value       = local.health_check_debug
}
