variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix used for resource names."
  type        = string
  default     = "plane-ce"
}

variable "tags" {
  description = "Common tags applied to supported resources."
  type        = map(string)
  default     = {}
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "Two availability zones used for public/private subnets."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least two availability zones are required."
  }
}

variable "db_name" {
  description = "Aurora PostgreSQL database name."
  type        = string
  default     = "plane"
}

variable "db_username" {
  description = "Aurora PostgreSQL master username."
  type        = string
  default     = "plane_admin"
}

variable "db_password" {
  description = "Aurora PostgreSQL master password."
  type        = string
  sensitive   = true
}

variable "db_engine_version" {
  description = "Aurora PostgreSQL engine version supporting Serverless v2 auto-pause."
  type        = string
  default     = "15.7"
}

variable "db_min_acu" {
  description = "Minimum Aurora Serverless v2 ACU (use 0 to allow auto-pause)."
  type        = number
  default     = 0
}

variable "db_max_acu" {
  description = "Maximum Aurora Serverless v2 ACU."
  type        = number
  default     = 1
}

variable "db_auto_pause_seconds" {
  description = "Seconds until Aurora auto-pause."
  type        = number
  default     = 600
}

variable "plane_bucket_name" {
  description = "Optional explicit S3 bucket name."
  type        = string
  default     = ""
}

variable "enable_s3_lifecycle_transition" {
  description = "Enable lifecycle transition for old uploads to reduce storage costs."
  type        = bool
  default     = false
}

variable "s3_transition_days" {
  description = "Days before transitioning uploads to STANDARD_IA."
  type        = number
  default     = 30
}

variable "alb_ingress_cidrs" {
  description = "CIDRs allowed to access the ALB. Restrict if fronting only via CloudFront."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS listeners and CloudFront custom domain."
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Optional custom domain for CloudFront."
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Optional Route53 hosted zone ID for creating alias record."
  type        = string
  default     = ""
}

variable "api_image" {
  description = "Plane backend image URI."
  type        = string
  default     = "makeplane/plane-backend:latest"
}

variable "web_image" {
  description = "Plane frontend image URI."
  type        = string
  default     = "makeplane/plane-frontend:latest"
}

variable "worker_image" {
  description = "Plane worker image URI."
  type        = string
  default     = "makeplane/plane-backend:latest"
}

variable "beat_image" {
  description = "Plane beat image URI."
  type        = string
  default     = "makeplane/plane-backend:latest"
}

variable "create_elasticache_redis" {
  description = "Create managed ElastiCache Redis (always-on cost) when true."
  type        = bool
  default     = false
}

variable "external_redis_url" {
  description = "Redis URL used when neither ElastiCache nor Fargate Redis are enabled."
  type        = string
  default     = "redis://localhost:6379"
}

variable "create_fargate_redis" {
  description = "Run Redis as a small ECS/Fargate service for lower idle cost patterns."
  type        = bool
  default     = false
}

variable "ecs_use_private_subnets" {
  description = "Run ECS services in private subnets (requires additional egress strategy)."
  type        = bool
  default     = false
}

variable "web_desired_count" {
  description = "Desired task count for Plane web service. Keep 0 for scale-to-zero baseline."
  type        = number
  default     = 0
}

variable "api_desired_count" {
  description = "Desired task count for Plane API service. Keep 0 for scale-to-zero baseline."
  type        = number
  default     = 0
}

variable "worker_desired_count" {
  description = "Desired task count for worker service."
  type        = number
  default     = 0
}

variable "beat_desired_count" {
  description = "Desired task count for beat service."
  type        = number
  default     = 0
}

variable "fargate_cpu" {
  description = "Fargate CPU units for web/api tasks."
  type        = number
  default     = 256
}

variable "fargate_memory" {
  description = "Fargate memory (MiB) for web/api tasks."
  type        = number
  default     = 512
}

variable "enable_wake_api" {
  description = "Expose wake Lambda via API Gateway HTTP API."
  type        = bool
  default     = true
}

variable "idle_minutes_before_shutdown" {
  description = "Minutes of ALB inactivity before shutdown lambda scales services to zero."
  type        = number
  default     = 15
}
