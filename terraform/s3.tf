resource "aws_s3_bucket" "plane_uploads" {
  bucket = var.plane_bucket_name != "" ? var.plane_bucket_name : null

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-uploads" })
}

resource "aws_s3_bucket_public_access_block" "plane_uploads" {
  bucket = aws_s3_bucket.plane_uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "plane_uploads" {
  bucket = aws_s3_bucket.plane_uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "plane_uploads" {
  count  = var.enable_s3_lifecycle_transition ? 1 : 0
  bucket = aws_s3_bucket.plane_uploads.id

  rule {
    id     = "uploads-transition"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = var.s3_transition_days
      storage_class = "STANDARD_IA"
    }
  }
}
