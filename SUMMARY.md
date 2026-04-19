# Serverless-friendly Plane CE deployment on AWS

## Overview

Plane Community Edition (CE) is an open-source project management platform with a Django backend, React/Next.js frontend, PostgreSQL, and Redis, typically deployed via Docker Compose or Kubernetes. The goal is to run Plane on AWS as “serverless as possible” with automatic scale-to-zero after inactivity while preserving data and enabling fast resume.[^1][^2][^3]

This document outlines an AWS architecture, concrete service choices, autoscaling-to-zero strategies, and implementation details (networking, security, IaC direction) optimized for a single/light user with minimal costs.

## Plane CE architecture and requirements

Plane’s core components:

- API/backend: Django app using PostgreSQL for persistence and Redis for background jobs and caching.[^4][^3]
- Frontend: React/Next.js web, historically separate `web` and `admin` services in docker-compose.[^5][^1]
- Background workers: Celery-style workers plus a beat/scheduler and sometimes a separate real-time collaboration/AI service depending on version.[^1][^4]
- Data stores: PostgreSQL (Postgres 15.5 in default Docker) and Redis.[^6]

Official deployment methods include Docker Compose, Kubernetes (Helm charts), Docker Swarm, and Docker single-container for evaluation. Plane CE recommends external Postgres and storage for production use.[^7][^2][^8][^9][^10][^6]

For AGPL-3.0 CE you can self-host with Docker or Kubernetes with no user limits.[^2]

## Constraints and goals

Target scenario:

- Very low-traffic, likely single-user or small internal team.
- Needs to feel reasonably snappy when "woken up" (acceptable cold start is a few to tens of seconds, not minutes).
- Infrastructure should scale to zero compute when idle to minimize costs.
- Data durability must not depend on ephemeral containers.

Key design goals:

- Compute scale-to-zero for backend, frontend, and workers.
- Database as close to "serverless" and scale-to-zero as practical while remaining compatible (Aurora Serverless v2).
- Minimal operational overhead: avoid managing EC2 manually; leverage managed services where possible.
- Reasonable security posture: VPC isolation, least-privilege IAM, TLS.

## High-level AWS architecture

Recommended architecture for Plane CE with scale-to-zero characteristics:

- Frontend and backend (API + Celery worker + beat) on AWS ECS Fargate using Plane CE Docker images.[^5][^1]
- Postgres on Amazon Aurora PostgreSQL Serverless v2 with auto-pause to 0 ACUs after X minutes of inactivity.[^11][^12]
- Redis on Amazon ElastiCache if you want managed Redis (always-on), or a small Fargate Redis container if you prefer more aggressive scale-to-zero with some cold-start overhead.
- Static assets/file uploads on Amazon S3 with Plane configured to use S3 storage.[^6][^5]
- Application entry via Amazon CloudFront + Application Load Balancer (ALB) for HTTPS, domain management, and caching.
- Optional API Gateway + Lambda "wake" endpoint for explicit wake events if you want a thin trigger surface.

This layout keeps persistent state (database + S3) on managed storage while application containers and optionally Redis can be fully stopped when idle.

## Components and service choices

### Database: Aurora PostgreSQL Serverless v2

Aurora Serverless v2 now supports scaling to 0 ACUs with automatic pause/resume for Aurora PostgreSQL 13.15+, 14.12+, 15.7+, and 16.3. You configure this by setting minimum capacity to 0 ACUs and enabling auto-pause, with `SecondsUntilAutoPause` between 300 seconds and 86,400 seconds.[^13][^14][^12][^15][^11]

Properties relevant to this design:

- Auto-pause after X seconds of no connections; during pause there is no compute billing, only storage.[^16][^11]
- Resume typically in under about 15 seconds when new connections arrive, which is acceptable for a single-user internal tool.[^17][^18]
- Supported for Aurora PostgreSQL engine versions that are compatible with Postgres 15.x, aligning with Plane’s documented default of Postgres 15.5.[^13][^6]

Plane can be configured to use an external PostgreSQL instance via environment variables or `DATABASE_URL`. For this architecture, Aurora Serverless v2 is recommended over RDS standard instances because it offers auto-pause and per-second ACU billing.[^6]

### Application: ECS Fargate tasks

Plane’s Docker images are published and intended for Docker Compose and Kubernetes. These containers map naturally onto ECS services and tasks:[^3][^7][^1][^5]

- `plane-backend`: Django API (and maybe also worker) container.
- `plane-frontend`: Next.js/React front-end.
- `plane-worker`: background Celery worker.
- `plane-beat`: scheduler.

The example Compose file from community resources shows frontend `makeplane/plane-frontend:latest` and backend `makeplane/plane-backend:latest` images, with Redis and Postgres containers.[^5]

On ECS Fargate, define the following task definitions:

- `plane-api-task`: backend container + sidecar for logging.
- `plane-web-task`: frontend container.
- `plane-worker-task`: worker container.
- Optional: combine beat + worker in one task for simplicity.

For "serverless" behavior:

- Run API and web tasks behind an Application Load Balancer with ECS Service autoscaling.
- Configure desired count to 0 when idle, and 1 when you need the service. There is no built-in "scale to zero" trigger, so implement this via a custom Lambda scheduler or based on CloudWatch metrics.
- Alternatively, use Fargate tasks as on-demand jobs triggered by an HTTP wake event (via Lambda) that starts tasks, waits for them to be running, then redirects the client.

Cold start considerations:

- Fargate task start times for moderately sized images (few hundred MB) are on the order of tens of seconds due to image pull; minimizing image size and using regional ECR can help.[^19][^5]
- For single-user, a 30–90-second first-hit delay can be acceptable if it removes ongoing compute costs.[^19]

### Redis: ElastiCache vs. Fargate

Plane uses Redis for background jobs and caching.[^4][^1][^6]

Options:

- Managed Redis (ElastiCache):
  - Always-on, cannot auto-pause, but smallest node classes are inexpensive.
  - Simplest operationally; required if you want instant readiness when ECS tasks start.
- Redis on Fargate:
  - Put Redis in its own ECS service or task that is started/stopped along with Plane.
  - Redis data is ephemeral, but Plane treats Redis mostly as transient job/caching layer; durable state lives in Postgres.

For minimal cost in a single-user non-critical deployment, Redis on Fargate is acceptable, understanding that queued jobs disappear on stop. If background jobs are important, ElastiCache is safer.

### Storage: S3

Plane can be configured to use external storage such as S3, and official docs emphasize configuring external storage for production.[^7][^6]

Best practice:

- Create a dedicated S3 bucket for Plane uploads.
- Configure lifecycle policies to transition older objects to cheaper storage classes if needed.
- Grant Plane backend an IAM role with least-privilege access (bucket read/write, no public access by default).

### Ingress: CloudFront, ALB, and routing

Plane expects to be served on a single domain (or subdomain) for web and API.

Recommended stack:

- CloudFront distribution with:
  - Origin: ALB.
  - Default behavior: forward all paths, or split behaviors for static assets if you later separate them.
  - Viewer protocol policy: redirect HTTP to HTTPS.
- ALB:
  - Target group for Plane web ECS service.
  - Optional second target group for API if you separate it by path.
- Route 53 alias record pointing your domain to CloudFront.

This allows TLS termination at CloudFront and/or ALB, caching static assets, and restricting direct access to Plane only through the CDN.

## Scale-to-zero strategy

### Database auto-pause

Aurora Serverless v2 auto-pause:

- Configure cluster min capacity to 0 ACUs and enable `SecondsUntilAutoPause` (5–15 minutes is reasonable).[^12][^15][^11]
- Ensure no persistent monitoring connections or long-lived idle sessions, because any open connection prevents pause.[^20][^16]
- When paused, Aurora charges only for storage, not compute; resume on first connection in around 15 seconds.[^18][^11][^17]

This delivers near-full scale-to-zero of database compute while keeping durable state intact.

### ECS tasks scale-to-zero

ECS itself does not have a native "scale to zero after X minutes idle" feature for services, but you can approximate this behavior.

Approach:

- Define ECS services for web and API with desired count normally 0.
- Provide a Lambda-based "wake" mechanism that:
  - On HTTP request, checks if tasks are running; if not, updates service desired count to 1 and polls ECS until healthy.
  - Once healthy, returns a `302` redirect to the actual Plane URL.

For automatic shutdown:

- A second Lambda scheduled by EventBridge (e.g., every 5 minutes) checks CloudWatch metrics and/or ALB access logs.
- If there has been no request within the last X minutes, it sets ECS service desired count back to 0.

This pattern mirrors serverless gating around Fargate and has been used for similar "on-demand" workloads.

Alternatively, for even simpler ops:

- Use one ECS task for Plane (web + API + worker in a single task definition) started on demand via `RunTask` from a Lambda, then stopped by another Lambda after idle period.
- This sacrifices auto-restarts on failure but keeps things minimal for a single-user experimental deployment.

### Cold start expectations

Expect total cold-start path:

- Lambda wake logic: a few hundred milliseconds.
- ECS task startup: 30–90 seconds depending on image size and healthchecks.[^19][^5]
- Aurora resume from 0 ACUs: approximately up to 15 seconds.[^17][^12][^18]

End-to-end first-hit delay of roughly 45–120 seconds is realistic but acceptable in exchange for near-zero idle compute costs.

## Security and networking

Key security and network controls:

- VPC:
  - Place ECS tasks and Aurora cluster in private subnets.
  - Use public subnets only for ALB (if not fully behind CloudFront).
- Security groups:
  - Aurora SG allowing inbound only from ECS tasks SG.
  - Redis SG allowing inbound only from ECS tasks SG.
  - ALB SG allowing inbound from CloudFront IP ranges or 0.0.0.0/0 if using TLS and WAF.
- IAM:
  - Task role for ECS backend task with:
    - S3 bucket access (list/get/put for specific bucket prefix).
    - CloudWatch logs write permissions.
  - Execution role for ECS to pull from ECR and write logs.
  - Lambda roles for wake and shutdown Lambdas with least privilege: ECS `UpdateService`, `DescribeServices`, `RunTask`, `StopTask` and CloudWatch/ALB log read as needed.
- TLS:
  - ACM certificate for your domain attached to CloudFront and/or ALB.
  - Enforce HTTPS-only at the edge.

Plane’s own authentication and authorization run at the application level; combine with AWS security to protect underlying infra.

## Implementation steps

### 1. Prepare Plane images

- Use official Plane CE images from Docker Hub or GitHub registry configured for CE.[^3][^5]
- Optionally build your own images from `makeplane/plane` repo Dockerfiles for API and web if you need customizations.[^1]
- Push images to Amazon ECR for faster pulls in your region.

### 2. Provision Aurora Serverless v2

- Create an Aurora PostgreSQL Serverless v2 cluster (version compatible with Postgres 15.x), in private subnets.
- Set minimum capacity to 0 ACUs and maximum to a small value suitable for your usage.
- Enable automatic pause with `SecondsUntilAutoPause` around 300–900 seconds initially.[^15][^11][^12]
- Record connection endpoint, database name, user, and password for Plane configuration.

### 3. Configure S3 storage

- Create an S3 bucket for Plane uploads.
- Block public access at bucket level; use presigned URLs or application proxying if you need public file access.
- Create an IAM policy granting write/read access to the bucket.

### 4. Create ECS cluster and task definitions

- Create an ECS cluster using Fargate as capacity provider.
- Define task definitions:
  - `plane-backend` task with environment variables:
    - `DATABASE_URL` or `PGHOST`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`, etc., pointing to Aurora.[^6]
    - `REDIS_URL` pointing to Redis.
    - Storage-related variables for S3 (bucket name, region, etc.).[^6]
  - `plane-frontend` task with `NEXT_PUBLIC_API_BASE_URL` pointing to backend.[^5]
  - Optional combined task for a simpler deployment.

Allocate minimal Fargate resources (e.g., 0.25 vCPU/0.5–1 GB RAM) since traffic is low, scaling up later if needed.[^2][^19]

### 5. Redis deployment

- Option A: Create an ElastiCache Redis cluster in private subnets and set `REDIS_URL` to point to it.
- Option B: Create a Fargate-based Redis task and service; start/stop it along with Plane tasks.

### 6. Set up ALB and CloudFront

- Create an ALB with a target group for Plane web ECS service.
- Configure ECS service for web (and optionally API) with ALB integration and health checks.
- Create a CloudFront distribution pointing to ALB, with ACM certificate for your domain.
- Create Route 53 DNS record pointing domain to CloudFront.

### 7. Implement wake and shutdown Lambdas

- Wake Lambda:
  - Exposed via API Gateway HTTP API or Lambda Function URL.
  - On invocation:
    - Call `DescribeServices` to check if Plane ECS service has running tasks.
    - If not, call `UpdateService` to set desired count to 1.
    - Poll until tasks are healthy (with timeout).
    - Return HTTP redirect to primary Plane URL.
- Shutdown Lambda:
  - Scheduled via EventBridge rule (e.g., every 5 minutes).
  - Checks recent requests via CloudWatch metrics (ALB `RequestCount` or access logs) or Plane app logs.
  - If no activity since threshold, call `UpdateService` to set desired count to 0.

This pattern aligns with scale-to-zero gating while keeping the external entrypoint stable.

## UX and usability considerations

Trade-offs of aggressive scale-to-zero:

- First request after idle period will incur cold start delays from both ECS and Aurora.[^12][^17][^19]
- Once running, performance is normal; autoscaling is trivial (keep single task for now).

Mitigations:

- For a single user who anticipates usage, consider a "Wake Plane" button or bookmark pointing to the wake endpoint, so they can pre-warm the app before active use.
- Set auto-pause thresholds high enough that short breaks do not cause frequent cold starts.
- Optionally keep only the backend always-on at minimal capacity and scale the frontend/worker to zero, trading some cost for better UX.

## Cost characteristics

Cost drivers:

- Aurora Serverless v2: billed per-second ACUs when not paused, and storage always.[^11][^17][^12]
- ECS Fargate: billed per vCPU-second and GB-second for running tasks only.[^19]
- Redis: ElastiCache always-on cost vs. Fargate ephemeral cost.
- CloudFront, ALB, S3, and Lambda: low for a single-user, mostly per-request and data-transfer-based.

With scale-to-zero and a single-user, expected monthly costs can be kept very low because:

- Aurora spends much of the time paused.[^11][^17]
- ECS tasks run only when the app is actively used.
- S3, CloudFront, and Lambda costs at small scale are typically a few dollars combined.

## Summary of recommended pattern

- Use Plane CE Docker images on ECS Fargate for web, API, and workers, with very small task sizes and on-demand startup.[^3][^1][^5]
- Use Aurora PostgreSQL Serverless v2 with min capacity 0 and auto-pause for the database.[^13][^12][^11]
- Use S3 for file storage and optionally Redis on Fargate for aggressive cost optimization.[^7][^6]
- Front Plane behind CloudFront + ALB, and add Lambda-based wake/shutdown automation to approximate serverless scale-to-zero behavior.
- Accept 45–120-second cold starts after long idle periods in exchange for near-zero idle compute spend.

---

## References

1. [docker-compose.yml - makeplane/plane - GitHub](https://github.com/makeplane/plane/blob/preview/docker-compose.yml) - Open-source Jira, Linear, Monday, and ClickUp alternative. Plane is a modern project management plat...

2. [Open Source Project Management Software - Plane](https://plane.so/open-source) - Open source project management with work items, cycles, wiki, and views. Run on Docker/K8s, own your...

3. [Introducing Plane: Simple, Extensible, Open-Source Project Management Tool](https://betterprogramming.pub/introducing-plane-simple-extensible-open-source-project-management-tool-d56dfac886ed?gi=a290996fef45) - Manage issues, sprints, and product roadmaps with peace of mind

4. [Plane: open-source project management with a surprisingly clean ...](https://www.codeline.co/thoughts/repo-review/2023/plane-open-source-project-management) - Plane is an open-source Jira/Linear alternative built on Django and React. What makes it worth looki...

5. [Plane: Plan, track, and execute work in one unified workspace.](https://awesome-docker-compose.com/plane) - Plan and execute work with flexible views, built-in documentation, and AI agents. Manage projects se...

6. [Configure external services - Plane Developer Documentation](https://developers.plane.so/self-hosting/govern/database-and-storage) - Provide the URL of your external PostgreSQL instance if you want to switch from the default Plane co...

7. [Docker Compose - Plane Developer Documentation](https://developers.plane.so/self-hosting/methods/docker-compose) - This guide shows you the steps to deploy a self-hosted instance of Plane using Docker. TIP. If you w...

8. [Self Hosted - Plane](https://plane.so/self-hosted) - Advanced mode connects your own Postgres, Redis, and S3. Kubernetes (Helm Charts). Production-grade ...

9. [Deploy Plane on your infrastructure - Plane Developer Documentation](https://developers.plane.so/self-hosting/overview) - Upgrade Community to Commercial Edition ... Deployment methods ​. Choose the deployment method that ...

10. [Official Helm charts of Plane - GitHub](https://github.com/makeplane/helm-charts) - This repository contains the official Helm charts for deploying Plane on Kubernetes. The charts are ...

11. [Scaling to Zero ACUs with automatic pause and resume for Aurora ...](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2-auto-pause.html) - You can specify that Aurora Serverless v2 DB instances scale down to zero ACUs and automatically pau...

12. [Introducing scaling to 0 capacity with Amazon Aurora Serverless v2](https://aws.amazon.com/blogs/database/introducing-scaling-to-0-capacity-with-amazon-aurora-serverless-v2/) - Amazon Aurora Serverless v2 now supports scaling capacity down to 0 ACUs, enabling you to optimize c...

13. [Aurora Serverless v2 Adds Zero-Capacity Scaling for True Serverless](https://www.infoq.com/news/2024/12/aurora-serverless-zero-capacity/) - Amazon Aurora Serverless v2 has recently announced that it now supports scaling to zero capacity, en...

14. [Amazon Aurora Serverless v2 supports scaling to zero ...](https://www.linkedin.com/posts/orlyandico_amazon-aurora-serverless-v2-supports-scaling-activity-7265253649314955264-FFBW) - One of the most-asked for features from v1 is back: Aurora Serverless v2 now supports scale to zero,...

15. [Response Structure](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/rds/client/modify_db_cluster.html)

16. [Enable Aurora Serverless AutoPause - Trend Micro](https://www.trendmicro.com/cloudoneconformity/knowledge-base/aws/RDS/enable-aurora-serverless-autopause.html) - Ensure that AutoPause feature is enabled for your Amazon Aurora Serverless clusters.

17. [Scaling to Zero with Amazon Aurora Serverless v2](https://dev.to/aws-builders/scaling-to-zero-with-amazon-aurora-serverless-v2-553n) - The new version v2 of Amazon Aurora Serverless has made improvements in providing scaling support...

18. [Aurora Serverless v2 Scales to Zero: Now, What? - Neon](https://neon.com/blog/aurora-serverless-v2-scales-to-zero-now-what) - You asked for it, AWS delivered: Aurora Serverless v2 now scales to zero. What does it mean for Auro...

19. [How long to spin up an ecs fargate task for a 500mb docket image, what if it runs for 30s and then exit 0? How much should i be charged for? Does it spin up faster with more ram/cpu allocation?](https://www.perplexity.ai/search/5ef0396b-1a73-412f-ba83-ddf2c1b18048) - ECS Fargate tasks with a 500MB Docker image typically take 30-90 seconds to fully spin up from initi...

20. [Amazon Aurora Serverless – The Sleeping Beauty](https://www.percona.com/blog/amazon-aurora-serverless-the-sleeping-beauty/) - Amazon Aurora Serverless pause helps limit running costs for idle applications, great for test and d...

