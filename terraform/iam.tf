data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  name               = "${local.name_prefix}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  name               = "${local.name_prefix}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "ecs_task" {
  statement {
    sid = "S3Uploads"
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = [
      aws_s3_bucket.plane_uploads.arn,
      "${aws_s3_bucket.plane_uploads.arn}/*"
    ]
  }

  statement {
    sid = "CloudWatchLogs"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ecs_task" {
  name   = "${local.name_prefix}-ecs-task-policy"
  policy = data.aws_iam_policy_document.ecs_task.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_task" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = aws_iam_policy.ecs_task.arn
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scale_lambda" {
  name               = "${local.name_prefix}-scale-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "scale_lambda" {
  statement {
    actions = [
      "ecs:DescribeServices",
      "ecs:UpdateService"
    ]
    resources = [
      aws_ecs_service.api.id,
      aws_ecs_service.web.id,
      aws_ecs_service.worker.id,
      aws_ecs_service.beat.id
    ]
  }

  statement {
    actions   = ["ecs:ListServices"]
    resources = ["*"]
  }

  statement {
    actions = [
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:GetMetricData"
    ]
    resources = ["*"]
  }

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "scale_lambda" {
  name   = "${local.name_prefix}-scale-lambda-policy"
  policy = data.aws_iam_policy_document.scale_lambda.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "scale_lambda" {
  role       = aws_iam_role.scale_lambda.name
  policy_arn = aws_iam_policy.scale_lambda.arn
}
