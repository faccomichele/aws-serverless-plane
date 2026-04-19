resource "aws_cloudfront_distribution" "plane" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront for Plane"
  default_root_object = ""

  aliases = var.domain_name != "" ? [var.domain_name] : []

  origin {
    domain_name = aws_lb.plane.dns_name
    origin_id   = "plane-alb-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "plane-alb-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = true
      headers      = ["*"]

      cookies {
        forward = "all"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.domain_name == ""
    acm_certificate_arn            = var.domain_name != "" ? var.certificate_arn : null
    ssl_support_method             = var.domain_name != "" ? "sni-only" : null
    minimum_protocol_version       = var.domain_name != "" ? "TLSv1.2_2021" : "TLSv1"
  }

  price_class = "PriceClass_100"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-cloudfront" })
}
