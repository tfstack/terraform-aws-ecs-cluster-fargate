# AWS CloudMap HTTP Namespace
resource "aws_service_discovery_http_namespace" "this" {
  count = var.create_namespace ? 1 : 0

  name        = var.namespace_name
  description = var.namespace_description

  tags = merge(
    {
      Name = var.namespace_name
    },
    var.tags
  )
}

# AWS CloudMap Private DNS Namespace
resource "aws_service_discovery_private_dns_namespace" "this" {
  count = var.create_private_dns_namespace ? 1 : 0

  name        = var.namespace_name
  description = var.namespace_description
  vpc         = var.vpc_id

  tags = merge(
    {
      Name = var.namespace_name
    },
    var.tags
  )
}

# AWS CloudMap Public DNS Namespace
resource "aws_service_discovery_public_dns_namespace" "this" {
  count = var.create_public_dns_namespace ? 1 : 0

  name        = var.namespace_name
  description = var.namespace_description

  tags = merge(
    {
      Name = var.namespace_name
    },
    var.tags
  )
}

# AWS CloudMap Services
resource "aws_service_discovery_service" "services" {
  for_each = var.services

  name          = each.value.name
  description   = try(each.value.description, null)
  namespace_id  = local.namespace_id
  force_destroy = true

  # DNS config only for DNS namespaces (private/public), not HTTP namespaces
  dynamic "dns_config" {
    for_each = var.enable_dns_config && (var.create_private_dns_namespace || var.create_public_dns_namespace) ? [1] : []
    content {
      namespace_id = local.namespace_id

      dns_records {
        ttl  = try(each.value.dns_ttl, var.dns_ttl)
        type = try(each.value.dns_record_type, var.dns_record_type)
      }

      routing_policy = try(each.value.routing_policy, var.routing_policy)
    }
  }

  # Standard health check configuration
  # - Only supported for public DNS namespaces
  # - Uses HTTP/HTTPS health checks with configurable resource path
  # - Mutually exclusive with health_check_custom_config
  # - failure_threshold is deprecated by AWS and always set to 1
  dynamic "health_check_config" {
    for_each = (
      try(each.value.health_check_config, null) != null &&
      var.enable_health_checks &&
      var.create_public_dns_namespace &&
      !try(each.value.health_check_custom_config, false)
    ) ? [each.value.health_check_config] : []

    content {
      resource_path     = health_check_config.value.resource_path
      type              = health_check_config.value.type
      failure_threshold = try(health_check_config.value.failure_threshold, 3)
    }
  }

  # Custom health check configuration - conditional based on service settings
  # - Only supported for private DNS namespaces
  # - Uses instance-level health check reporting
  # - Mutually exclusive with health_check_config
  # - failure_threshold must be explicitly set to 1 to avoid Terraform drift (see AWS provider issue #35559)
  dynamic "health_check_custom_config" {
    for_each = (
      try(each.value.health_check_custom_config, false) &&
      var.enable_health_checks &&
      var.create_private_dns_namespace &&
      try(each.value.health_check_config, null) == null
    ) ? [1] : []
    content {
      failure_threshold = try(each.value.custom_health_check_failure_threshold, 1)
    }
  }

  tags = merge(
    {
      Name = each.value.name
    },
    try(each.value.tags, {}),
    var.tags
  )

  lifecycle {
    # Allow health check configuration to be updated
    ignore_changes = [
      # Only ignore changes that don't affect health check configuration
    ]
  }
}

# IAM Role for ECS Service Discovery (if enabled)
resource "aws_iam_role" "ecs_service_discovery" {
  count = var.create_ecs_service_discovery_role && length(var.services) > 0 ? 1 : 0

  name = "${var.namespace_name}-service-discovery-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for ECS Service Discovery
resource "aws_iam_role_policy" "ecs_service_discovery" {
  count = var.create_ecs_service_discovery_role && length(var.services) > 0 ? 1 : 0

  name = "${var.namespace_name}-service-discovery-policy"
  role = aws_iam_role.ecs_service_discovery[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "servicediscovery:RegisterInstance",
          "servicediscovery:DeregisterInstance",
          "servicediscovery:GetInstancesHealthStatus",
          "servicediscovery:UpdateInstanceCustomHealthStatus"
        ]
        Resource = [for service in aws_service_discovery_service.services : service.arn]
      }
    ]
  })
}

# Local values for namespace ID and health check debugging
locals {
  namespace_id = var.existing_namespace_id != null ? var.existing_namespace_id : (
    var.create_private_dns_namespace ? aws_service_discovery_private_dns_namespace.this[0].id : (
      var.create_public_dns_namespace ? aws_service_discovery_public_dns_namespace.this[0].id : (
        var.create_namespace ? aws_service_discovery_http_namespace.this[0].id : null
      )
    )
  )

  # Debug information for health check configuration
  health_check_debug = {
    for service_name, service in var.services : service_name => {
      health_check_custom_config_requested = try(service.health_check_custom_config, false)
      health_check_config_provided         = try(service.health_check_config, null) != null
      enable_health_checks                 = var.enable_health_checks
      is_private_namespace                 = var.create_private_dns_namespace
      is_public_namespace                  = var.create_public_dns_namespace
      is_http_namespace                    = var.create_namespace
      using_existing_namespace             = var.existing_namespace_id != null

      # Final health check decisions
      will_create_custom_health_check = (
        try(service.health_check_custom_config, false) &&
        var.enable_health_checks &&
        (var.create_private_dns_namespace ||
        (var.existing_namespace_id != null && !var.create_public_dns_namespace && !var.create_namespace))
      )
      will_create_standard_health_check = (
        try(service.health_check_config, null) != null &&
        var.enable_health_checks &&
        var.create_public_dns_namespace &&
        !try(service.health_check_custom_config, false)
      )
    }
  }
}
