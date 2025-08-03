data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Private DNS Namespace for internal service discovery
module "service_discovery_private" {
  count  = length(var.ecs_services) > 0 && anytrue([for s in var.ecs_services : s.enable_private_service_discovery]) ? 1 : 0
  source = "tfstack/cloudmap/aws"

  create_private_dns_namespace = true
  namespace_name               = "${var.cluster_name}-${var.suffix}-internal"
  namespace_description        = "Private DNS namespace for ECS service discovery"
  vpc_id                       = var.vpc.id

  services = {
    for s in var.ecs_services : s.name => {
      name                       = s.name
      health_check_custom_config = true
    }
    if s.enable_private_service_discovery
  }

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-private-service-discovery"
    Purpose = "Private ECS Service Discovery"
  })
}

# Public DNS Namespace for external service discovery
module "service_discovery_public" {
  count  = length(var.ecs_services) > 0 && anytrue([for s in var.ecs_services : s.enable_public_service_discovery]) ? 1 : 0
  source = "./modules/cloudmap"

  create_public_dns_namespace = true
  namespace_name              = "${var.cluster_name}-${var.suffix}.com"
  namespace_description       = "Public DNS namespace for external service discovery"

  services = {
    for s in var.ecs_services : s.name => {
      name = s.name
      health_check_config = {
        resource_path     = s.health_check_path
        type              = "HTTP"
        failure_threshold = 3
      }
    }
    if s.enable_public_service_discovery
  }

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-public-service-discovery"
    Purpose = "Public ECS Service Discovery"
  })
}


resource "aws_cloudwatch_log_group" "this" {
  count = var.create_cloudwatch_log_group ? 1 : 0

  name              = "/aws/ecs/${var.cluster_name}-${var.suffix}"
  retention_in_days = var.cloudwatch_log_group_retention_days

  lifecycle {
    prevent_destroy = false
  }

  tags = merge(var.tags, { Name = var.cluster_name })
}

resource "aws_cloudwatch_log_group" "ecs_services" {
  for_each = var.create_cloudwatch_log_group ? { for s in var.ecs_services : s.name => s } : {}

  name              = "/aws/ecs/${var.cluster_name}-${var.suffix}-${each.key}"
  retention_in_days = var.cloudwatch_log_group_retention_days

  lifecycle {
    prevent_destroy = false
  }

  tags = merge(var.tags, { Name = "${var.cluster_name}-${var.suffix}-${each.key}" })
}

module "s3_bucket" {
  count  = var.create_s3_logging_bucket ? 1 : 0
  source = "tfstack/s3/aws"

  bucket_name   = var.cluster_name
  bucket_suffix = var.suffix

  tags = merge(var.tags, { Name = var.cluster_name })
}

resource "aws_ecs_cluster" "this" {
  name = var.cluster_name

  dynamic "configuration" {
    for_each = [{}]

    content {
      execute_command_configuration {
        logging = (var.create_cloudwatch_log_group || var.create_s3_logging_bucket) ? "OVERRIDE" : "DEFAULT"

        dynamic "log_configuration" {
          for_each = (var.create_cloudwatch_log_group || var.create_s3_logging_bucket) ? [{}] : []

          content {
            cloud_watch_log_group_name = try(aws_cloudwatch_log_group.this[0].name, null)
            s3_bucket_name             = try(module.s3_bucket[0].bucket_id, null)
            s3_key_prefix              = var.s3_key_prefix
          }
        }
      }
    }
  }

  dynamic "setting" {
    for_each = flatten([var.cluster_settings])

    content {
      name  = setting.value.name
      value = setting.value.value
    }
  }

  tags = merge(var.tags, { Name = var.cluster_name })
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  count = length(var.capacity_providers) > 0 ? 1 : 0

  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = distinct([for k, v in var.capacity_providers : try(v.name, k)])

  dynamic "default_capacity_provider_strategy" {
    for_each = var.capacity_providers
    iterator = strategy

    content {
      capacity_provider = try(strategy.value.name, strategy.key)
      base              = try(strategy.value.default_capacity_provider_strategy.base, null)
      weight            = try(strategy.value.default_capacity_provider_strategy.weight, null)
    }
  }
}

resource "aws_ecs_task_definition" "this" {
  for_each = { for s in var.ecs_services : s.name => s }

  family                   = "${var.cluster_name}-${each.key}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value.cpu
  memory                   = each.value.memory

  task_role_arn         = lookup(each.value, "task_role_arn", null)
  execution_role_arn    = length(each.value.execution_role_policies) > 0 ? aws_iam_role.ecs_task_execution[each.key].arn : null
  container_definitions = each.value.container_definitions

  tags = each.value.task_tags
}

module "aws_alb" {
  for_each = { for s in var.ecs_services : s.name => s if s.enable_alb }

  source = "tfstack/alb/aws"

  name   = each.key
  suffix = var.suffix
  vpc_id = var.vpc.id

  public_subnet_ids   = var.vpc.public_subnets[*].id
  public_subnet_cidrs = var.vpc.public_subnets[*].cidr

  enable_https     = each.value.enable_https
  http_port        = try(jsondecode(each.value.container_definitions)[0].portMappings[0].containerPort, null)
  target_http_port = try(jsondecode(each.value.container_definitions)[0].portMappings[0].containerPort, null)
  target_type      = "ip"

  enable_availability_zone_all = false
  allowed_http_cidrs           = each.value.allowed_http_cidrs
}

# ECS services with autoscaling enabled (ignore desired_count drift)
resource "aws_ecs_service" "with_autoscaling" {
  for_each = { for s in var.ecs_services : s.name => s if s.enable_autoscaling }

  name                 = "${var.cluster_name}-${each.key}"
  cluster              = aws_ecs_cluster.this.id
  task_definition      = aws_ecs_task_definition.this[each.key].arn
  launch_type          = "FARGATE"
  force_new_deployment = each.value.enable_private_service_discovery ? true : each.value.force_new_deployment

  enable_ecs_managed_tags = each.value.enable_ecs_managed_tags
  propagate_tags          = each.value.propagate_tags
  scheduling_strategy     = "REPLICA"
  desired_count           = each.value.desired_count

  deployment_minimum_healthy_percent = each.value.deployment_minimum_healthy_percent
  deployment_maximum_percent         = each.value.deployment_maximum_percent

  # Health check grace period for CloudMap service discovery
  health_check_grace_period_seconds = each.value.enable_private_service_discovery ? 60 : null

  network_configuration {
    subnets          = each.value.subnet_ids
    security_groups  = each.value.security_groups
    assign_public_ip = each.value.assign_public_ip
  }

  dynamic "load_balancer" {
    for_each = (
      each.value.enable_alb &&
      contains(keys(module.aws_alb), each.key)
      ? [coalesce(module.aws_alb[each.key].http_target_group_arn, module.aws_alb[each.key].https_target_group_arn)] : []
    )

    content {
      target_group_arn = load_balancer.value
      container_name   = each.value.name
      container_port = try(
        jsondecode(each.value.container_definitions)[0].portMappings[0].containerPort,
        null
      )
    }
  }

  # Service discovery registration (validation ensures only one type is enabled)
  dynamic "service_registries" {
    for_each = concat(
      each.value.enable_private_service_discovery && length(module.service_discovery_private) > 0 ?
      [module.service_discovery_private[0].service_arns[each.key]] : [],
      each.value.enable_public_service_discovery && length(module.service_discovery_public) > 0 ?
      [module.service_discovery_public[0].service_arns[each.key]] : []
    )

    content {
      registry_arn = service_registries.value
      # Port is required for public service discovery with Route 53 health checks
      port = each.value.enable_public_service_discovery ? (
        try(jsondecode(each.value.container_definitions)[0].portMappings[0].containerPort, null)
      ) : null
    }
  }

  tags = each.value.service_tags

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# ECS services without autoscaling (enforce desired_count)
resource "aws_ecs_service" "without_autoscaling" {
  for_each = { for s in var.ecs_services : s.name => s if !s.enable_autoscaling }

  name                 = "${var.cluster_name}-${each.key}"
  cluster              = aws_ecs_cluster.this.id
  task_definition      = aws_ecs_task_definition.this[each.key].arn
  launch_type          = "FARGATE"
  force_new_deployment = each.value.enable_private_service_discovery ? true : each.value.force_new_deployment

  enable_ecs_managed_tags = each.value.enable_ecs_managed_tags
  propagate_tags          = each.value.propagate_tags
  scheduling_strategy     = "REPLICA"
  desired_count           = each.value.desired_count

  deployment_minimum_healthy_percent = each.value.deployment_minimum_healthy_percent
  deployment_maximum_percent         = each.value.deployment_maximum_percent

  # Health check grace period for CloudMap service discovery
  health_check_grace_period_seconds = each.value.enable_private_service_discovery ? 60 : null

  network_configuration {
    subnets          = each.value.subnet_ids
    security_groups  = each.value.security_groups
    assign_public_ip = each.value.assign_public_ip
  }

  dynamic "load_balancer" {
    for_each = (
      each.value.enable_alb &&
      contains(keys(module.aws_alb), each.key)
      ? [coalesce(module.aws_alb[each.key].http_target_group_arn, module.aws_alb[each.key].https_target_group_arn)] : []
    )

    content {
      target_group_arn = load_balancer.value
      container_name   = each.value.name
      container_port = try(
        jsondecode(each.value.container_definitions)[0].portMappings[0].containerPort,
        null
      )
    }
  }

  # Service discovery registration (validation ensures only one type is enabled)
  dynamic "service_registries" {
    for_each = concat(
      each.value.enable_private_service_discovery && length(module.service_discovery_private) > 0 ?
      [module.service_discovery_private[0].service_arns[each.key]] : [],
      each.value.enable_public_service_discovery && length(module.service_discovery_public) > 0 ?
      [module.service_discovery_public[0].service_arns[each.key]] : []
    )

    content {
      registry_arn = service_registries.value
      # Port is required for public service discovery with Route 53 health checks
      port = each.value.enable_public_service_discovery ? (
        try(jsondecode(each.value.container_definitions)[0].portMappings[0].containerPort, null)
      ) : null
    }
  }

  tags = each.value.service_tags
}

resource "aws_appautoscaling_target" "this" {
  for_each = { for asg in var.ecs_autoscaling : asg.service_name => asg }

  resource_id        = "service/${var.cluster_name}/${each.value.service_name}"
  scalable_dimension = each.value.scalable_dimension
  service_namespace  = "ecs"

  min_capacity = each.value.min_capacity
  max_capacity = each.value.max_capacity

  depends_on = [
    aws_ecs_service.with_autoscaling,
    aws_ecs_service.without_autoscaling
  ]
}

resource "aws_appautoscaling_policy" "this" {
  for_each = { for s in var.ecs_autoscaling : s.service_name => s }

  name              = each.value.policy_name
  policy_type       = each.value.policy_type
  service_namespace = "ecs"

  resource_id        = aws_appautoscaling_target.this[each.key].resource_id
  scalable_dimension = each.value.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value = each.value.target_value

    dynamic "predefined_metric_specification" {
      for_each = each.value.predefined_metric_type != null ? [each.value.predefined_metric_type] : []
      content {
        predefined_metric_type = predefined_metric_specification.value
      }
    }
  }

  depends_on = [
    aws_appautoscaling_target.this
  ]
}

resource "aws_iam_role" "ecs_task_execution" {
  for_each = { for s in var.ecs_services : s.name => s if length(s.execution_role_policies) > 0 }

  name = "${var.cluster_name}-${each.key}-task-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, { Name = "${each.key}-task-exec" })
}

resource "aws_iam_policy" "ecs_cloudwatch_logs" {
  for_each = { for s in var.ecs_services : s.name => s if var.create_cloudwatch_log_group }

  name        = "${var.cluster_name}-${var.suffix}-${each.key}-logs"
  description = "IAM policy to allow ECS Task Execution for ${each.key} to write logs to CloudWatch."

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "CloudWatchLogsWriteAccess",
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ecs/${var.cluster_name}-${var.suffix}-${each.key}*"
      },
      {
        Sid    = "CloudWatchLogsReadAccess",
        Effect = "Allow",
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ],
        Resource = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_cloudwatch_logs" {
  for_each = { for s in var.ecs_services : s.name => s if var.create_cloudwatch_log_group }

  role       = aws_iam_role.ecs_task_execution[each.key].name
  policy_arn = aws_iam_policy.ecs_cloudwatch_logs[each.key].arn
}

resource "aws_iam_policy" "ecs_s3_logging" {
  for_each = { for s in var.ecs_services : s.name => s if var.create_s3_logging_bucket }

  name        = "${var.cluster_name}-${each.key}-s3-logs"
  description = "IAM policy to allow ECS Task Execution for ${each.key} to write logs to S3."

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:GetBucketLocation"
        ],
        Resource = [
          "arn:aws:s3:::${module.s3_bucket[0].bucket_id}",
          "arn:aws:s3:::${module.s3_bucket[0].bucket_id}/${var.s3_key_prefix}${each.key}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_s3_logging" {
  for_each = { for s in var.ecs_services : s.name => s if var.create_s3_logging_bucket && length(s.execution_role_policies) > 0 }

  role       = aws_iam_role.ecs_task_execution[each.key].name
  policy_arn = aws_iam_policy.ecs_s3_logging[each.key].arn
}

resource "aws_iam_policy" "ecs_ecr_access" {
  for_each = { for s in var.ecs_services : s.name => s }

  name        = "${var.cluster_name}-${each.key}-ecr-access"
  description = "IAM policy for ECS Task Execution to pull images from ECR."

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "arn:aws:ecr:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:repository/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_ecr_access" {
  for_each = { for s in var.ecs_services : s.name => s if length(s.execution_role_policies) > 0 }

  role       = aws_iam_role.ecs_task_execution[each.key].name
  policy_arn = aws_iam_policy.ecs_ecr_access[each.key].arn
}
