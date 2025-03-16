# terraform-aws-ecs-cluster-fargate

Terraform module to create an ECS Fargate cluster with optional CloudWatch monitoring and logging support

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | 5.84.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.84.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_aws_alb"></a> [aws\_alb](#module\_aws\_alb) | tfstack/alb/aws | n/a |
| <a name="module_s3_bucket"></a> [s3\_bucket](#module\_s3\_bucket) | tfstack/s3/aws | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_appautoscaling_policy.this](https://registry.terraform.io/providers/hashicorp/aws/5.84.0/docs/resources/appautoscaling_policy) | resource |
| [aws_appautoscaling_target.this](https://registry.terraform.io/providers/hashicorp/aws/5.84.0/docs/resources/appautoscaling_target) | resource |
| [aws_cloudwatch_log_group.ecs_services](https://registry.terraform.io/providers/hashicorp/aws/5.84.0/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.this](https://registry.terraform.io/providers/hashicorp/aws/5.84.0/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/5.84.0/docs/resources/ecs_cluster) | resource |
| [aws_ecs_cluster_capacity_providers.this](https://registry.terraform.io/providers/hashicorp/aws/5.84.0/docs/resources/ecs_cluster_capacity_providers) | resource |
| [aws_ecs_service.this](https://registry.terraform.io/providers/hashicorp/aws/5.84.0/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.this](https://registry.terraform.io/providers/hashicorp/aws/5.84.0/docs/resources/ecs_task_definition) | resource |
| [aws_iam_policy.ecs_cloudwatch_logs](https://registry.terraform.io/providers/hashicorp/aws/5.84.0/docs/resources/iam_policy) | resource |
| [aws_iam_policy.ecs_ecr_access](https://registry.terraform.io/providers/hashicorp/aws/5.84.0/docs/resources/iam_policy) | resource |
| [aws_iam_policy.ecs_s3_logging](https://registry.terraform.io/providers/hashicorp/aws/5.84.0/docs/resources/iam_policy) | resource |
| [aws_iam_role.ecs_task_execution](https://registry.terraform.io/providers/hashicorp/aws/5.84.0/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.ecs_cloudwatch_logs](https://registry.terraform.io/providers/hashicorp/aws/5.84.0/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ecs_ecr_access](https://registry.terraform.io/providers/hashicorp/aws/5.84.0/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ecs_s3_logging](https://registry.terraform.io/providers/hashicorp/aws/5.84.0/docs/resources/iam_role_policy_attachment) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/5.84.0/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/5.84.0/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_capacity_providers"></a> [capacity\_providers](#input\_capacity\_providers) | Map of Fargate capacity providers with required strategy settings. | <pre>map(object({<br/>    default_capacity_provider_strategy = object({<br/>      weight = number<br/>      base   = optional(number, 0)<br/>    })<br/>  }))</pre> | <pre>{<br/>  "FARGATE": {<br/>    "default_capacity_provider_strategy": {<br/>      "base": 20,<br/>      "weight": 50<br/>    }<br/>  },<br/>  "FARGATE_SPOT": {<br/>    "default_capacity_provider_strategy": {<br/>      "weight": 50<br/>    }<br/>  }<br/>}</pre> | no |
| <a name="input_cloudwatch_log_group_retention_days"></a> [cloudwatch\_log\_group\_retention\_days](#input\_cloudwatch\_log\_group\_retention\_days) | The number of days to retain logs for the cluster. | `number` | `30` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the ECS cluster. | `string` | n/a | yes |
| <a name="input_cluster_settings"></a> [cluster\_settings](#input\_cluster\_settings) | List of cluster settings configurations. | `list(any)` | `[]` | no |
| <a name="input_create_cloudwatch_log_group"></a> [create\_cloudwatch\_log\_group](#input\_create\_cloudwatch\_log\_group) | Enable or disable the creation of a CloudWatch Log Group for ECS logs. | `bool` | `false` | no |
| <a name="input_create_s3_logging_bucket"></a> [create\_s3\_logging\_bucket](#input\_create\_s3\_logging\_bucket) | Enable or disable the creation of an S3 bucket for ECS logs. | `bool` | `false` | no |
| <a name="input_ecs_autoscaling"></a> [ecs\_autoscaling](#input\_ecs\_autoscaling) | List of ECS service auto scaling configurations | <pre>list(object({<br/>    service_name       = string<br/>    min_capacity       = number<br/>    max_capacity       = number<br/>    scalable_dimension = string<br/>    policy_name        = string<br/>    policy_type        = string<br/>    target_value       = number<br/><br/>    predefined_metric_type = optional(string)<br/>    custom_metric = optional(object({<br/>      metric_name = string<br/>      namespace   = string<br/>      statistic   = string<br/>      dimensions = optional(list(object({<br/>        name  = string<br/>        value = string<br/>      })), [])<br/>    }))<br/>  }))</pre> | `[]` | no |
| <a name="input_ecs_services"></a> [ecs\_services](#input\_ecs\_services) | List of ECS services to be created | <pre>list(object({<br/>    name                  = string<br/>    desired_count         = optional(number, 1)<br/>    cpu                   = optional(string, "256")<br/>    memory                = optional(string, "512")<br/>    container_definitions = string<br/><br/>    execution_role_policies            = optional(list(string), [])<br/>    enable_execute_command             = optional(bool, false)<br/>    force_new_deployment               = optional(bool, false)<br/>    deployment_minimum_healthy_percent = optional(number, 100)<br/>    deployment_maximum_percent         = optional(number, 200)<br/><br/>    subnet_ids       = list(string)<br/>    security_groups  = list(string)<br/>    assign_public_ip = optional(bool, false)<br/><br/>    enable_alb   = optional(bool, false)<br/>    enable_https = optional(bool, false)<br/><br/>    enable_ecs_managed_tags = optional(bool, false)<br/>    propagate_tags          = optional(string, "TASK_DEFINITION")<br/>    service_tags            = optional(map(string))<br/>    task_tags               = optional(map(string))<br/>  }))</pre> | `[]` | no |
| <a name="input_s3_key_prefix"></a> [s3\_key\_prefix](#input\_s3\_key\_prefix) | Prefix for logs stored in the S3 bucket. | `string` | `"logs/"` | no |
| <a name="input_service_connect_defaults"></a> [service\_connect\_defaults](#input\_service\_connect\_defaults) | Default Service Connect configuration for the ECS cluster. | <pre>object({<br/>    namespace = string<br/>  })</pre> | `null` | no |
| <a name="input_suffix"></a> [suffix](#input\_suffix) | Optional suffix for resource names. | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources. | `map(string)` | `{}` | no |
| <a name="input_vpc"></a> [vpc](#input\_vpc) | VPC configuration settings. | <pre>object({<br/>    id = string<br/>    private_subnets = list(object({<br/>      id   = string<br/>      cidr = string<br/>    }))<br/>    public_subnets = list(object({<br/>      id   = string<br/>      cidr = string<br/>    }))<br/>  })</pre> | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alb_arns"></a> [alb\_arns](#output\_alb\_arns) | ALB ARNs for services using ALB. |
| <a name="output_alb_dns_names"></a> [alb\_dns\_names](#output\_alb\_dns\_names) | DNS names of the ALBs. |
| <a name="output_alb_target_group_arns"></a> [alb\_target\_group\_arns](#output\_alb\_target\_group\_arns) | Target Group ARNs for ALBs. |
| <a name="output_cloudwatch_cluster_log_group"></a> [cloudwatch\_cluster\_log\_group](#output\_cloudwatch\_cluster\_log\_group) | CloudWatch Log Group for the ECS cluster. |
| <a name="output_cloudwatch_service_log_groups"></a> [cloudwatch\_service\_log\_groups](#output\_cloudwatch\_service\_log\_groups) | List of CloudWatch Log Groups for ECS services. |
| <a name="output_ecs_autoscaling_policies"></a> [ecs\_autoscaling\_policies](#output\_ecs\_autoscaling\_policies) | Map of ECS service auto-scaling policies. |
| <a name="output_ecs_autoscaling_targets"></a> [ecs\_autoscaling\_targets](#output\_ecs\_autoscaling\_targets) | Map of ECS service auto-scaling targets. |
| <a name="output_ecs_cluster_arn"></a> [ecs\_cluster\_arn](#output\_ecs\_cluster\_arn) | The ARN of the created ECS cluster. |
| <a name="output_ecs_cluster_id"></a> [ecs\_cluster\_id](#output\_ecs\_cluster\_id) | The ID of the created ECS cluster. |
| <a name="output_ecs_cluster_s3_logging_bucket"></a> [ecs\_cluster\_s3\_logging\_bucket](#output\_ecs\_cluster\_s3\_logging\_bucket) | S3 bucket name for ECS logs if created. |
| <a name="output_ecs_services"></a> [ecs\_services](#output\_ecs\_services) | Map of ECS services with their ARNs. |
| <a name="output_ecs_task_definitions"></a> [ecs\_task\_definitions](#output\_ecs\_task\_definitions) | Map of ECS task definitions with their ARNs. |
| <a name="output_ecs_task_execution_roles"></a> [ecs\_task\_execution\_roles](#output\_ecs\_task\_execution\_roles) | IAM roles assigned to ECS task execution. |
