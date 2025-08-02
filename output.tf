output "ecs_cluster_id" {
  description = "The ID of the created ECS cluster."
  value       = aws_ecs_cluster.this.id
}

output "ecs_cluster_arn" {
  description = "The ARN of the created ECS cluster."
  value       = aws_ecs_cluster.this.arn
}

output "ecs_services" {
  description = "Map of ECS services with their ARNs."
  value = merge(
    {
      for s in aws_ecs_service.with_autoscaling :
      s.name => {
        arn = s.id
      }
    },
    {
      for s in aws_ecs_service.without_autoscaling :
      s.name => {
        arn = s.id
      }
    }
  )
}

output "ecs_task_definitions" {
  description = "Map of ECS task definitions with their ARNs."
  value = {
    for td in aws_ecs_task_definition.this :
    td.family => {
      arn = td.arn
    }
  }
}

output "cloudwatch_cluster_log_group" {
  description = "CloudWatch Log Group for the ECS cluster."
  value       = length(aws_cloudwatch_log_group.this) > 0 ? aws_cloudwatch_log_group.this[0].name : null
}

output "cloudwatch_service_log_groups" {
  description = "List of CloudWatch Log Groups for ECS services."
  value       = [for lg in aws_cloudwatch_log_group.ecs_services : lg.name]
}

output "ecs_cluster_s3_logging_bucket" {
  description = "S3 bucket name for ECS logs if created."
  value       = try(module.s3_bucket[0].bucket_id, null)
}

output "ecs_autoscaling_targets" {
  description = "Map of ECS service auto-scaling targets."
  value = {
    for asg in aws_appautoscaling_target.this :
    asg.resource_id => {
      min_capacity = asg.min_capacity
      max_capacity = asg.max_capacity
      dimension    = asg.scalable_dimension
    }
  }
}

output "ecs_autoscaling_policies" {
  description = "Map of ECS service auto-scaling policies."
  value = {
    for policy in aws_appautoscaling_policy.this :
    policy.resource_id => {
      policy_name = policy.name
    }
  }
}

output "ecs_task_execution_roles" {
  description = "IAM roles assigned to ECS task execution."
  value = {
    for role in aws_iam_role.ecs_task_execution :
    role.name => role.arn
  }
}

output "alb_arns" {
  description = "ALB ARNs for services using ALB."
  value = {
    for k, alb in module.aws_alb : k => alb.alb_arn
  }
}

output "alb_dns_names" {
  description = "DNS names of the ALBs."
  value = {
    for k, alb in module.aws_alb : k => alb.alb_dns
  }
}

output "alb_target_group_arns" {
  description = "Target Group ARNs for ALBs."
  value = {
    for k, alb in module.aws_alb : k => coalesce(alb.http_target_group_arn, alb.https_target_group_arn)
  }
}

output "service_discovery_namespace_id" {
  description = "ID of the service discovery namespace"
  value       = length(module.service_discovery_private) > 0 ? module.service_discovery_private[0].namespace_id : null
}

output "service_discovery_namespace_name" {
  description = "Name of the service discovery namespace"
  value       = length(module.service_discovery_private) > 0 ? module.service_discovery_private[0].namespace_name : null
}

output "service_discovery_services" {
  description = "Map of service discovery services"
  value       = length(module.service_discovery_private) > 0 ? module.service_discovery_private[0].services : {}
}

output "service_discovery_service_arns" {
  description = "Map of service names to their ARNs for service discovery"
  value       = length(module.service_discovery_private) > 0 ? module.service_discovery_private[0].service_arns : {}
}

output "public_service_discovery_namespace_id" {
  description = "ID of the public service discovery namespace"
  value       = length(module.service_discovery_public) > 0 ? module.service_discovery_public[0].namespace_id : null
}

output "public_service_discovery_namespace_name" {
  description = "Name of the public service discovery namespace"
  value       = length(module.service_discovery_public) > 0 ? module.service_discovery_public[0].namespace_name : null
}

output "public_service_discovery_services" {
  description = "Map of public service discovery services"
  value       = length(module.service_discovery_public) > 0 ? module.service_discovery_public[0].services : {}
}

output "public_service_discovery_service_arns" {
  description = "Map of service names to their ARNs for public service discovery"
  value       = length(module.service_discovery_public) > 0 ? module.service_discovery_public[0].service_arns : {}
}
