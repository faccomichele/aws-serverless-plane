# Terraform infrastructure for Plane CE on AWS

This folder contains a cost-aware Terraform baseline for deploying Plane CE with:

- ECS Fargate services (web/api/worker/beat)
- Aurora PostgreSQL Serverless v2
- S3 for uploads
- ALB + CloudFront ingress
- Optional Route53 alias
- Lambda + EventBridge automation for wake and idle shutdown
- Optional Redis choices (external, Fargate, or ElastiCache)

## Usage

1. Copy example variables:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Set at least `db_password` and optionally domain/certificate values.

3. Initialize and validate:

   ```bash
   terraform init
   terraform fmt -recursive
   terraform validate
   ```

4. Plan/apply:

   ```bash
   terraform plan
   terraform apply
   ```

## Cost notes

- ECS services default to desired count `0` for scale-to-zero baseline.
- Aurora defaults to min ACU `0` and sets idle pause configuration (where supported by selected engine/platform).
- ElastiCache Redis is disabled by default (always-on cost).
- CloudFront uses `PriceClass_100`.
