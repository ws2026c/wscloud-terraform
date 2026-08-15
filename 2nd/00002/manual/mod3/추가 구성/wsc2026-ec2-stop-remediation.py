import json
import os
import time
from datetime import datetime, timezone

import boto3

ec2_client = boto3.client("ec2")
sns_client = boto3.client("sns")

SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")


def publish_alert(event_type, detail, action):
    sns_client.publish(
        TopicArn=SNS_TOPIC_ARN,
        Message=json.dumps({
            "event": event_type,
            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "detail": detail,
            "action": action,
        }),
    )


def handler(event, context):
    detail = event.get("detail", {})
    instance_id = detail.get("instance-id") or os.environ.get("INSTANCE_ID")

    started = False
    for _ in range(90):
        try:
            ec2_client.start_instances(InstanceIds=[instance_id])
            started = True
            break
        except Exception as exc:
            message = str(exc)
            if "IncorrectInstanceState" in message or "IncorrectState" in message:
                time.sleep(3)
                continue
            print(f"start instance failed: {exc}")
            break

    print(f"start_instances: started={started}")

    publish_alert(
        "EC2_STOPPED",
        f"Instance {instance_id} was stopped and has been restarted",
        "RESTORED",
    )
    return {"statusCode": 200}