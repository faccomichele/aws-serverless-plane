import datetime as dt
import os

import boto3


def _sum_requests(cw_client, alb_suffix, minutes, namespace, metric_name):
    end = dt.datetime.now(dt.timezone.utc)
    start = end - dt.timedelta(minutes=minutes)

    metric = cw_client.get_metric_statistics(
        Namespace=namespace,
        MetricName=metric_name,
        Dimensions=[{"Name": "LoadBalancer", "Value": alb_suffix}],
        StartTime=start,
        EndTime=end,
        Period=min(max(minutes * 60, 60), 86400),
        Statistics=["Sum"]
    )

    datapoints = metric.get("Datapoints", [])
    return sum(p.get("Sum", 0) for p in datapoints)


def _scale_zero(ecs_client, cluster, service):
    ecs_client.update_service(cluster=cluster, service=service, desiredCount=0)


def handler(event, context):
    cluster = os.environ["ECS_CLUSTER"]
    services = [
        os.environ["WEB_SERVICE"],
        os.environ["API_SERVICE"],
        os.environ["WORKER_SERVICE"],
        os.environ["BEAT_SERVICE"],
    ]
    alb_suffix = os.environ["ALB_NAME"]
    idle_minutes = int(os.getenv("IDLE_MINUTES", "15"))
    namespace = os.getenv("METRIC_NAMESPACE", "AWS/ApplicationELB")
    metric_name = os.getenv("METRIC_NAME", "RequestCount")

    cw = boto3.client("cloudwatch")
    ecs = boto3.client("ecs")

    request_sum = _sum_requests(cw, alb_suffix, idle_minutes, namespace, metric_name)
    if request_sum > 0:
        return {"statusCode": 200, "body": "Activity detected; skipping shutdown."}

    for service in services:
        _scale_zero(ecs, cluster, service)

    return {"statusCode": 200, "body": "Scaled services to zero."}
