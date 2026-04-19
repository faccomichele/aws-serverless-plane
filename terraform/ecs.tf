resource "aws_cloudwatch_log_group" "plane" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = 7

  tags = local.common_tags
}

resource "aws_ecs_cluster" "plane" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = local.common_tags
}

resource "aws_service_discovery_private_dns_namespace" "plane" {
  count = var.create_fargate_redis ? 1 : 0

  name = "${local.name_prefix}.local"
  vpc  = aws_vpc.main.id

  tags = local.common_tags
}

resource "aws_service_discovery_service" "redis" {
  count = var.create_fargate_redis ? 1 : 0

  name = "redis"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.plane[0].id

    dns_records {
      type = "A"
      ttl  = 10
    }
  }
}

resource "aws_ecs_task_definition" "api" {
  family                   = "${local.name_prefix}-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name         = "plane-api"
      image        = var.api_image
      essential    = true
      portMappings = [{ containerPort = 8000, hostPort = 8000, protocol = "tcp" }]
      environment  = local.default_container_env
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.plane.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "api"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "web" {
  family                   = "${local.name_prefix}-web"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name         = "plane-web"
      image        = var.web_image
      essential    = true
      portMappings = [{ containerPort = 3000, hostPort = 3000, protocol = "tcp" }]
      environment = concat(local.default_container_env, [
        { name = "NEXT_PUBLIC_API_BASE_URL", value = var.domain_name != "" ? "https://${var.domain_name}" : "https://${aws_cloudfront_distribution.plane.domain_name}" }
      ])
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.plane.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "web"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "worker" {
  family                   = "${local.name_prefix}-worker"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name        = "plane-worker"
      image       = var.worker_image
      essential   = true
      command     = ["./bin/docker-entrypoint-worker.sh"]
      environment = local.default_container_env
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.plane.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "worker"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "beat" {
  family                   = "${local.name_prefix}-beat"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name        = "plane-beat"
      image       = var.beat_image
      essential   = true
      command     = ["./bin/docker-entrypoint-beat.sh"]
      environment = local.default_container_env
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.plane.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "beat"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "api" {
  name            = "${local.name_prefix}-api"
  cluster         = aws_ecs_cluster.plane.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.api_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.ecs_use_private_subnets ? aws_subnet.private[*].id : aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = var.ecs_use_private_subnets ? false : true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "plane-api"
    container_port   = 8000
  }

  depends_on = [aws_lb_listener.http]

  tags = local.common_tags
}

resource "aws_ecs_service" "web" {
  name            = "${local.name_prefix}-web"
  cluster         = aws_ecs_cluster.plane.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = var.web_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.ecs_use_private_subnets ? aws_subnet.private[*].id : aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = var.ecs_use_private_subnets ? false : true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "plane-web"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.http]

  tags = local.common_tags
}

resource "aws_ecs_service" "worker" {
  name            = "${local.name_prefix}-worker"
  cluster         = aws_ecs_cluster.plane.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = var.worker_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.ecs_use_private_subnets ? aws_subnet.private[*].id : aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = var.ecs_use_private_subnets ? false : true
  }

  tags = local.common_tags
}

resource "aws_ecs_service" "beat" {
  name            = "${local.name_prefix}-beat"
  cluster         = aws_ecs_cluster.plane.id
  task_definition = aws_ecs_task_definition.beat.arn
  desired_count   = var.beat_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.ecs_use_private_subnets ? aws_subnet.private[*].id : aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = var.ecs_use_private_subnets ? false : true
  }

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "redis" {
  count = var.create_fargate_redis ? 1 : 0

  family                   = "${local.name_prefix}-redis"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode([
    {
      name         = "redis"
      image        = "redis:7-alpine"
      essential    = true
      portMappings = [{ containerPort = 6379, hostPort = 6379, protocol = "tcp" }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.plane.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "redis"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "redis" {
  count = var.create_fargate_redis ? 1 : 0

  name            = "${local.name_prefix}-redis"
  cluster         = aws_ecs_cluster.plane.id
  task_definition = aws_ecs_task_definition.redis[0].arn
  desired_count   = var.redis_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.ecs_use_private_subnets ? aws_subnet.private[*].id : aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = var.ecs_use_private_subnets ? false : true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.redis[0].arn
  }

  tags = local.common_tags
}
