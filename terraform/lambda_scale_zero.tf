locals {
  wake_lambda_source = "${path.module}/lambda-src/wake.py"
  shutdown_source    = "${path.module}/lambda-src/shutdown.py"
}

data "archive_file" "wake" {
  type        = "zip"
  source_file = local.wake_lambda_source
  output_path = "${path.module}/lambda-src/wake.zip"
}

data "archive_file" "shutdown" {
  type        = "zip"
  source_file = local.shutdown_source
  output_path = "${path.module}/lambda-src/shutdown.zip"
}

resource "aws_lambda_function" "wake" {
  function_name    = "${local.name_prefix}-wake"
  role             = aws_iam_role.scale_lambda.arn
  runtime          = "python3.12"
  handler          = "wake.handler"
  filename         = data.archive_file.wake.output_path
  source_code_hash = data.archive_file.wake.output_base64sha256
  timeout          = 60

  environment {
    variables = {
      ECS_CLUSTER  = aws_ecs_cluster.plane.name
      WEB_SERVICE  = aws_ecs_service.web.name
      API_SERVICE  = aws_ecs_service.api.name
      REDIRECT_URL = var.domain_name != "" ? "https://${var.domain_name}" : "https://${aws_cloudfront_distribution.plane.domain_name}"
      WAKE_TIMEOUT = "240"
    }
  }

  tags = local.common_tags
}

resource "aws_lambda_function" "shutdown" {
  function_name    = "${local.name_prefix}-shutdown"
  role             = aws_iam_role.scale_lambda.arn
  runtime          = "python3.12"
  handler          = "shutdown.handler"
  filename         = data.archive_file.shutdown.output_path
  source_code_hash = data.archive_file.shutdown.output_base64sha256
  timeout          = 60

  environment {
    variables = {
      ECS_CLUSTER      = aws_ecs_cluster.plane.name
      WEB_SERVICE      = aws_ecs_service.web.name
      API_SERVICE      = aws_ecs_service.api.name
      WORKER_SERVICE   = aws_ecs_service.worker.name
      BEAT_SERVICE     = aws_ecs_service.beat.name
      ALB_NAME         = aws_lb.plane.arn_suffix
      IDLE_MINUTES     = tostring(var.idle_minutes_before_shutdown)
      METRIC_NAMESPACE = "AWS/ApplicationELB"
      METRIC_NAME      = "RequestCount"
    }
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_event_rule" "shutdown_schedule" {
  name                = "${local.name_prefix}-shutdown-schedule"
  description         = "Scale Plane ECS services down when idle"
  schedule_expression = "rate(5 minutes)"

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "shutdown" {
  rule      = aws_cloudwatch_event_rule.shutdown_schedule.name
  target_id = "shutdown-lambda"
  arn       = aws_lambda_function.shutdown.arn
}

resource "aws_lambda_permission" "shutdown_events" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.shutdown.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.shutdown_schedule.arn
}

resource "aws_apigatewayv2_api" "wake" {
  count = var.enable_wake_api ? 1 : 0

  name          = "${local.name_prefix}-wake-api"
  protocol_type = "HTTP"

  tags = local.common_tags
}

resource "aws_apigatewayv2_integration" "wake" {
  count = var.enable_wake_api ? 1 : 0

  api_id                 = aws_apigatewayv2_api.wake[0].id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.wake.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "wake" {
  count = var.enable_wake_api ? 1 : 0

  api_id    = aws_apigatewayv2_api.wake[0].id
  route_key = "GET /wake"
  target    = "integrations/${aws_apigatewayv2_integration.wake[0].id}"
}

resource "aws_apigatewayv2_stage" "wake" {
  count = var.enable_wake_api ? 1 : 0

  api_id      = aws_apigatewayv2_api.wake[0].id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "wake_api" {
  count = var.enable_wake_api ? 1 : 0

  statement_id  = "AllowInvokeFromHttpApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.wake.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.wake[0].execution_arn}/*/*"
}
