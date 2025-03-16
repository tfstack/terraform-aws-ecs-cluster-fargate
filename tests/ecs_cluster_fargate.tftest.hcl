run "setup_ecs" {
  module {
    source = "./tests/setup"
  }
}

run "ecs_cluster_test" {
  variables {
    cluster_name = run.setup_ecs.cluster_name
    suffix       = run.setup_ecs.suffix

    vpc = {
      id = run.setup_ecs.vpc_id
      private_subnets = [
        for i, subnet in run.setup_ecs.private_subnets :
        { id = subnet, cidr = run.setup_ecs.private_subnets_cidr_blocks[i] }
      ]
      public_subnets = [
        for i, subnet in run.setup_ecs.public_subnets :
        { id = subnet, cidr = run.setup_ecs.public_subnets_cidr_blocks[i] }
      ]
    }

    s3_key_prefix                       = "logs/"
    create_cloudwatch_log_group         = true
    cloudwatch_log_group_retention_days = 90
    create_s3_logging_bucket            = true

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
        name                 = run.setup_ecs.app_name
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
            name      = run.setup_ecs.app_name
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
                awslogs-group         = "/aws/ecs/${run.setup_ecs.cluster_name}-${run.setup_ecs.app_name}"
                awslogs-region        = run.setup_ecs.region
                awslogs-stream-prefix = "${run.setup_ecs.cluster_name}-nginx"
              }
            }
          }
        ])

        deployment_minimum_healthy_percent = 100
        deployment_maximum_percent         = 200
        health_check_grace_period_seconds  = 30

        subnet_ids       = run.setup_ecs.private_subnets
        security_groups  = [run.setup_ecs.security_group_id]
        assign_public_ip = false

        enable_alb              = true
        enable_ecs_managed_tags = true
        propagate_tags          = "TASK_DEFINITION"

        service_tags = {
          Environment = "test"
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
        service_name           = "${run.setup_ecs.cluster_name}-${run.setup_ecs.app_name}"
        min_capacity           = 3
        max_capacity           = 12
        scalable_dimension     = "ecs:service:DesiredCount"
        policy_name            = "scale-on-cpu"
        policy_type            = "TargetTrackingScaling"
        target_value           = 75
        predefined_metric_type = "ECSServiceAverageCPUUtilization"
      }
    ]

    tags = run.setup_ecs.tags
  }

  assert {
    condition     = length(module.s3_bucket) > 0
    error_message = "S3 bucket for logging does not exist."
  }

  assert {
    condition     = length(aws_ecs_cluster.this) > 0
    error_message = "ECS Cluster was not created successfully."
  }

  assert {
    condition     = length(aws_ecs_service.this) > 0
    error_message = "ECS Services were not created successfully."
  }

  assert {
    condition = alltrue([
      for s in keys(aws_ecs_service.this) : can(s)
    ])
    error_message = "ECS Services validation failed."
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.this) > 0
    error_message = "CloudWatch Log Group for ECS is missing."
  }

  assert {
    condition     = length(aws_appautoscaling_policy.this) > 0
    error_message = "ECS Autoscaling policies are missing."
  }

  assert {
    condition     = length(aws_iam_role.ecs_task_execution) > 0
    error_message = "IAM Role for ECS Task Execution is missing."
  }

  assert {
    condition     = length(aws_iam_policy.ecs_cloudwatch_logs) > 0
    error_message = "CloudWatch logging IAM policy is missing."
  }

  assert {
    condition     = length(aws_iam_policy.ecs_s3_logging) > 0
    error_message = "S3 logging IAM policy is missing."
  }

  assert {
    condition     = length(aws_iam_policy.ecs_ecr_access) > 0
    error_message = "ECR access IAM policy is missing."
  }
}
