# Terraform ECS Fargate Basic Configuration

This Terraform configuration demonstrates a **basic Amazon ECS cluster** setup using the **Fargate launch type**, including networking, security groups, logging, and autoscaling configurations.

## Features

This basic example demonstrates:

- **VPC Setup**: Creates a VPC with private and public subnets.
- **ECS Cluster**: Deploys an ECS cluster with **Fargate** and **Fargate Spot** capacity providers.
- **Security Groups**: Configures security groups for ECS tasks and ALB.
- **CloudWatch Logs**: Enables logging for ECS services.
- **Auto Scaling**: Configures basic ECS service autoscaling.
- **Application Load Balancer (ALB)**: ALB setup for ECS services.
- **Single Service**: Demonstrates a single web application service.

## What This Example Covers

This basic example shows the fundamental features of the ECS Fargate module:

- Basic cluster setup with capacity providers
- Single service deployment with ALB
- CloudWatch and S3 logging
- Basic autoscaling configuration
- VPC and security group setup

## What This Example Does NOT Cover

For more advanced features, see other examples:

- **Service Discovery**: See the `service-discovery` example
- **Multiple Services**: See the `complete` example (when available)
- **Advanced Autoscaling**: See examples with custom metrics
- **Service Connect**: See examples with service mesh features

## Usage

### **Initialize and Apply**

```bash
terraform init
terraform plan
terraform apply
```

### **Destroy Resources**

```bash
terraform destroy
```

> **Warning:** Running this example creates AWS resources that incur costs.

## Inputs

| Name                             | Description                                        | Type             | Default              |
|----------------------------------|------------------------------------------------|----------------|----------------------|
| `cluster_name`                   | ECS cluster name.                               | `string`        | `"cltest"`          |
| `suffix`                          | Random string suffix for unique names.         | `string`        | `""`                |
| `vpc`                             | VPC configuration with subnet details.         | `map(object)`   | `{}`                |
| `cluster_settings`                | ECS cluster settings like container insights.  | `list(map)`     | `[]`                |
| `create_cloudwatch_log_group`     | Enable CloudWatch logs for ECS.                | `bool`          | `true`              |
| `cloudwatch_log_group_retention_days` | Log retention period in days.            | `number`        | `90`                |
| `create_s3_logging_bucket`        | Enable S3 logging for ECS.                     | `bool`          | `true`              |
| `s3_key_prefix`                   | Prefix for logs stored in S3.                  | `string`        | `"logs/"`           |
| `capacity_providers`              | ECS capacity provider configurations.          | `map(object)`   | `{}`                |
| `ecs_services`                    | List of ECS services with configurations.      | `list(object)`  | `[]`                |
| `ecs_autoscaling`                 | ECS autoscaling policies.                      | `list(object)`  | `[]`                |

## Outputs

| Name                              | Description                                        |
|-----------------------------------|------------------------------------------------|
| `ecs_cluster_id`                   | The ARN of the ECS cluster.                     |
| `ecs_cluster_capacity_providers`   | The list of ECS cluster capacity providers.     |
| `ecs_service_names`                | The list of deployed ECS service names.        |
| `ecs_autoscaling_policies`         | The ECS autoscaling policy configurations.     |
| `ecs_iam_policy_arns`              | The ARNs of the IAM policies for ECS tasks.    |
| `ecs_s3_logging_bucket`            | The name of the S3 bucket for ECS logs.        |
| `ecs_cloudwatch_log_group`         | The name of the CloudWatch log group.          |

## Resources Created

- **VPC** with public and private subnets
- **Security Groups** for ECS tasks and ALB
- **ECS Cluster** with Fargate launch type
- **ECS Task Definitions and Services**
- **CloudWatch Log Groups** for ECS logging
- **S3 Bucket** for ECS log storage
- **IAM Roles and Policies** for ECS execution
- **Application Load Balancer (ALB)** (if enabled)
- **Auto Scaling Policies** for ECS services

This configuration demonstrates a **basic but functional ECS deployment** using AWS Fargate, suitable for learning and simple production workloads.
