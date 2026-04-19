resource "aws_route53_record" "plane" {
  count = var.route53_zone_id != "" && var.domain_name != "" ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.plane.domain_name
    zone_id                = aws_cloudfront_distribution.plane.hosted_zone_id
    evaluate_target_health = false
  }
}
