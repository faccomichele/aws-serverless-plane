locals {
  name_prefix = var.name_prefix

  common_tags = merge(
    var.tags,
    {
      ManagedBy = "terraform"
      Project   = local.name_prefix
    }
  )

  redis_url = var.create_elasticache_redis ? format("redis://%s:%d", aws_elasticache_replication_group.redis[0].primary_endpoint_address, 6379) : (
    var.create_fargate_redis ? format("redis://redis.%s:6379", aws_service_discovery_private_dns_namespace.plane[0].name) : var.external_redis_url
  )

  default_container_env = [
    { name = "DATABASE_HOST", value = aws_rds_cluster.aurora.endpoint },
    { name = "DATABASE_PORT", value = "5432" },
    { name = "DATABASE_NAME", value = var.db_name },
    { name = "DATABASE_USER", value = var.db_username },
    { name = "DATABASE_PASSWORD", value = var.db_password },
    { name = "REDIS_URL", value = local.redis_url },
    { name = "AWS_REGION", value = var.aws_region },
    { name = "AWS_STORAGE_BUCKET_NAME", value = aws_s3_bucket.plane_uploads.bucket }
  ]
}
