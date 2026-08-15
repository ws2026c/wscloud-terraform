import json
import os
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
    instance_id = os.environ.get("INSTANCE_ID")
    required_key = os.environ.get("REQUIRED_TAG_KEY", "Name")
    required_value = os.environ.get("REQUIRED_TAG_VALUE", "wsc2026-event-ec2")

    target = instance_id
    for arn in event.get("resources") or []:
        if ":instance/" in arn:
            target = arn.split("/")[-1]
            break

    restored = False
    try:
        tags = ec2_client.describe_tags(
            Filters=[{"Name": "resource-id", "Values": [target]}]
        )["Tags"]
        current = {t["Key"]: t["Value"] for t in tags}

        if current.get(required_key) != required_value:
            ec2_client.create_tags(
                Resources=[target],
                Tags=[{"Key": required_key, "Value": required_value}],
            )
            restored = True
    except Exception as exc:
        print(f"tag restore failed: {exc}")

    publish_alert(
        "TAG_CHANGED",
        f"Required tag '{required_key}' on {target} was changed"
        + (" and has been restored" if restored else ""),
        "RESTORED" if restored else "ALERT_ONLY",
    )
    return {"statusCode": 200}