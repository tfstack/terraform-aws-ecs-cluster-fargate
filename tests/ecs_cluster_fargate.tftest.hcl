run "ecs_cluster_test" {
  command = plan
  variables {
    cluster_name = "test-cluster"
    suffix       = "test"

    vpc = {
      id = "vpc-12345678"
      private_subnets = [
        { id = "subnet-12345678", cidr = "10.0.101.0/24" },
        { id = "subnet-23456789", cidr = "10.0.102.0/24" },
        { id = "subnet-34567890", cidr = "10.0.103.0/24" }
      ]
      public_subnets = [
        { id = "subnet-45678901", cidr = "10.0.1.0/24" },
        { id = "subnet-56789012", cidr = "10.0.2.0/24" },
        { id = "subnet-67890123", cidr = "10.0.3.0/24" }
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
        name                 = "web"
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
            name      = "web"
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
                awslogs-group         = "/aws/ecs/test-cluster-web"
                awslogs-region        = "ap-southeast-2"
                awslogs-stream-prefix = "test-cluster-nginx"
              }
            }
          }
        ])

        deployment_minimum_healthy_percent = 100
        deployment_maximum_percent         = 200
        health_check_grace_period_seconds  = 30

        subnet_ids       = ["subnet-12345678", "subnet-23456789", "subnet-34567890"]
        security_groups  = ["sg-12345678"]
        assign_public_ip = false

        enable_alb               = true
        enable_service_discovery = false # Explicitly set to false
        enable_ecs_managed_tags  = true
        propagate_tags           = "TASK_DEFINITION"

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
        service_name           = "test-cluster-web"
        min_capacity           = 3
        max_capacity           = 12
        scalable_dimension     = "ecs:service:DesiredCount"
        policy_name            = "scale-on-cpu"
        policy_type            = "TargetTrackingScaling"
        target_value           = 75
        predefined_metric_type = "ECSServiceAverageCPUUtilization"
      }
    ]

    tags = {
      Environment = "test"
      Project     = "example"
    }
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
    condition     = length(aws_ecs_service.with_autoscaling) + length(aws_ecs_service.without_autoscaling) > 0
    error_message = "ECS Services were not created successfully."
  }

  assert {
    condition = alltrue([
      for s in keys(aws_ecs_service.with_autoscaling) : can(s)
      ]) && alltrue([
      for s in keys(aws_ecs_service.without_autoscaling) : can(s)
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

run "ecs_cluster_with_service_discovery_test" {
  command = plan
  variables {
    cluster_name = "test-sd"
    suffix       = "sd"

    vpc = {
      id = "vpc-12345678"
      private_subnets = [
        { id = "subnet-12345678", cidr = "10.0.101.0/24" },
        { id = "subnet-23456789", cidr = "10.0.102.0/24" },
        { id = "subnet-34567890", cidr = "10.0.103.0/24" }
      ]
      public_subnets = [
        { id = "subnet-45678901", cidr = "10.0.1.0/24" },
        { id = "subnet-56789012", cidr = "10.0.2.0/24" },
        { id = "subnet-67890123", cidr = "10.0.3.0/24" }
      ]
    }

    s3_key_prefix                       = "logs/"
    create_cloudwatch_log_group         = true
    cloudwatch_log_group_retention_days = 90
    create_s3_logging_bucket            = true

    capacity_providers = {
      FARGATE = {
        default_capacity_provider_strategy = {
          weight = 100
          base   = 0
        }
      }
    }

    ecs_services = [
      {
        name                 = "backend"
        desired_count        = 2
        cpu                  = "256"
        memory               = "512"
        force_new_deployment = true

        execution_role_policies = [
          "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
          "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
        ]

        container_definitions = jsonencode([
          {
            name      = "backend"
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
                awslogs-group         = "/aws/ecs/test-cluster-sd-backend-service"
                awslogs-region        = "ap-southeast-2"
                awslogs-stream-prefix = "backend-service"
              }
            }
          }
        ])

        deployment_minimum_healthy_percent = 100
        deployment_maximum_percent         = 200

        subnet_ids       = ["subnet-12345678", "subnet-23456789", "subnet-34567890"]
        security_groups  = ["sg-12345678"]
        assign_public_ip = false

        enable_alb                       = false
        enable_private_service_discovery = true
        health_check_path                = "/"

        enable_ecs_managed_tags = true
        propagate_tags          = "TASK_DEFINITION"

        service_tags = {
          ServiceType = "backend"
          Purpose     = "service-discovery-test"
        }

        task_tags = {
          TaskType = "backend"
          Version  = "1.0"
        }
      },
      {
        name                 = "frontend"
        desired_count        = 2
        cpu                  = "256"
        memory               = "512"
        force_new_deployment = true

        execution_role_policies = [
          "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
          "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
        ]

        container_definitions = jsonencode([
          {
            name      = "frontend"
            image     = "nginx:latest"
            cpu       = 256
            memory    = 512
            essential = true
            portMappings = [{
              containerPort = 80
            }]
            environment = [
              {
                name  = "BACKEND_SERVICE"
                value = "http://backend-service.internal:80"
              }
            ]
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
                awslogs-group         = "/aws/ecs/test-cluster-sd-frontend-service"
                awslogs-region        = "ap-southeast-2"
                awslogs-stream-prefix = "frontend-service"
              }
            }
          }
        ])

        deployment_minimum_healthy_percent = 100
        deployment_maximum_percent         = 200

        subnet_ids       = ["subnet-45678901", "subnet-56789012", "subnet-67890123"]
        security_groups  = ["sg-12345678"]
        assign_public_ip = true

        enable_alb                       = true
        enable_private_service_discovery = true
        health_check_path                = "/"

        enable_ecs_managed_tags = true
        propagate_tags          = "TASK_DEFINITION"

        service_tags = {
          ServiceType = "frontend"
          Purpose     = "service-discovery-test"
        }

        task_tags = {
          TaskType = "frontend"
          Version  = "1.0"
        }
      }
    ]

    tags = {
      Environment = "test"
      Project     = "service-discovery-example"
    }
  }

  assert {
    condition     = length(aws_ecs_cluster.this) > 0
    error_message = "ECS Cluster was not created successfully."
  }

  assert {
    condition     = length(aws_ecs_service.with_autoscaling) + length(aws_ecs_service.without_autoscaling) > 0
    error_message = "ECS Services were not created successfully."
  }

  assert {
    condition = alltrue([
      for s in keys(aws_ecs_service.with_autoscaling) : can(s)
      ]) && alltrue([
      for s in keys(aws_ecs_service.without_autoscaling) : can(s)
    ])
    error_message = "ECS Services validation failed."
  }

  assert {
    condition     = length(module.service_discovery_private) > 0
    error_message = "Service discovery namespace was not created."
  }

  assert {
    condition     = length(module.service_discovery_private[0].service_arns) > 0
    error_message = "Service discovery services were not created."
  }

  assert {
    condition = alltrue([
      for s in keys(module.service_discovery_private[0].service_arns) : can(s)
    ])
    error_message = "Service discovery services validation failed."
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.this) > 0
    error_message = "CloudWatch Log Group for ECS is missing."
  }

  assert {
    condition     = length(aws_iam_role.ecs_task_execution) > 0
    error_message = "IAM Role for ECS Task Execution is missing."
  }
}
