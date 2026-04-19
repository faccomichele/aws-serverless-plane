import json
import os
import time

import boto3


def _service_running(ecs_client, cluster, service):
    response = ecs_client.describe_services(cluster=cluster, services=[service])
    svc = response["services"][0]
    return svc.get("runningCount", 0) > 0 and svc.get("deployments", [])[0].get("rolloutState") == "COMPLETED"


def _ensure_running(ecs_client, cluster, service):
    ecs_client.update_service(cluster=cluster, service=service, desiredCount=1)


def handler(event, context):
    cluster = os.environ["ECS_CLUSTER"]
    web_service = os.environ["WEB_SERVICE"]
    api_service = os.environ["API_SERVICE"]
    redirect_url = os.environ["REDIRECT_URL"]
    timeout_seconds = int(os.getenv("WAKE_TIMEOUT", "240"))

    ecs = boto3.client("ecs")

    if not _service_running(ecs, cluster, web_service):
        _ensure_running(ecs, cluster, web_service)
    if not _service_running(ecs, cluster, api_service):
        _ensure_running(ecs, cluster, api_service)

    start = time.time()
    while time.time() - start < timeout_seconds:
        web_ok = _service_running(ecs, cluster, web_service)
        api_ok = _service_running(ecs, cluster, api_service)
        if web_ok and api_ok:
            return {
                "statusCode": 302,
                "headers": {"Location": redirect_url},
                "body": ""
            }
        time.sleep(5)

    return {
        "statusCode": 202,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"message": "Plane is warming up, retry shortly."})
    }
