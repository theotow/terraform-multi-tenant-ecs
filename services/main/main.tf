resource "aws_cloudwatch_log_group" "main" {
  name              = "${var.name_prefix}-main"
  retention_in_days = 1
}

resource "aws_ecs_task_definition" "main" {
  family = "${var.name_prefix}-main"

  container_definitions = <<EOF
[
  {
    "name": "main",
    "image": "${var.image_url}",
    "cpu": 400,
    "memory": 320,
    "portMappings": [
      {
        "containerPort": 3000,
        "hostPort": 0
      }
    ],
    "environment": [
    {
      "name": "NODE_ENV",
      "value": "${var.environment}"
    },
    {
      "name": "PORT",
      "value": "3000"
    }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-region": "${var.region}",
        "awslogs-group": "${var.name_prefix}-main",
        "awslogs-stream-prefix": "${var.name_prefix}"
      }
    }
  }
]
EOF
  tags = {
    Environment = var.environment
    Name        = var.name
  }
}

resource "aws_ecs_service" "main" {
  name = "${var.name_prefix}-main"
  cluster = var.cluster_id
  task_definition = aws_ecs_task_definition.main.arn

  desired_count = 1
  load_balancer {
    target_group_arn = "${var.alb_arn}"
    container_name = "main"
    container_port = 3000
  }

  deployment_maximum_percent = 200
  deployment_minimum_healthy_percent = 100
}
