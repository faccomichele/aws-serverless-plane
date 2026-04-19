output "vpc_id" {
  value = aws_vpc.main.id
}

output "alb_dns_name" {
  value = aws_lb.plane.dns_name
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.plane.domain_name
}

output "plane_url" {
  value = var.domain_name != "" ? "https://${var.domain_name}" : "https://${aws_cloudfront_distribution.plane.domain_name}"
}

output "wake_endpoint" {
  value = var.enable_wake_api ? "${aws_apigatewayv2_stage.wake[0].invoke_url}wake" : null
}

output "aurora_endpoint" {
  value = aws_rds_cluster.aurora.endpoint
}

output "s3_bucket_name" {
  value = aws_s3_bucket.plane_uploads.bucket
}
