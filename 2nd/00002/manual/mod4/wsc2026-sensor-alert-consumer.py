import base64
import json
import os

import boto3

SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")
S3_BUCKET = os.environ.get("S3_BUCKET")

sns_client = boto3.client("sns")
s3_client = boto3.client("s3")


def build_message(payload):
    return (
        f"[WSC2026 Sensor Alert]\n"
        f"sensorId    : {payload.get('sensorId')}\n"
        f"timestamp   : {payload.get('timestamp')}\n"
        f"temperature : {payload.get('temperature')}\n"
        f"humidity    : {payload.get('humidity')}\n"
        f"location    : {payload.get('location')}\n"
        f"reason      : {payload.get('alert_reason')}"
    )


def save_log(payload):
    sensor_id = payload.get("sensorId", "unknown")
    timestamp = str(payload.get("timestamp", ""))
    date = timestamp[:10] if len(timestamp) >= 10 else "unknown"

    key = f"alert/{sensor_id}/{date}/{timestamp}.json"

    s3_client.put_object(
        Bucket=S3_BUCKET,
        Key=key,
        Body=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        ContentType="application/json; charset=utf-8",
    )
    return key


def handler(event, context):
    records = []
    for partition_records in (event.get("records") or {}).values():
        records.extend(partition_records)

    print(f"Processing batch: {len(records)} alert messages")

    handled = 0

    for record in records:
        raw = record.get("value")
        if raw is None:
            continue

        try:
            payload = json.loads(base64.b64decode(raw).decode("utf-8"))
        except Exception as exc:
            print(f"skip malformed record: {exc}")
            continue

        sensor_id = payload.get("sensorId", "unknown")

        try:
            sns_client.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject=f"Sensor Alert - {sensor_id}",
                Message=build_message(payload),
            )
        except Exception as exc:
            print(f"{sensor_id}: sns publish failed: {exc}")

        try:
            key = save_log(payload)
            print(f"{sensor_id}: ALERT saved - s3://{S3_BUCKET}/{key}")
        except Exception as exc:
            print(f"{sensor_id}: s3 put failed: {exc}")

        handled += 1

    return {"handled": handled, "total": len(records)}