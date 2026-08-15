import base64
import json
import os

import boto3

DDB_TABLE = os.environ.get("DDB_TABLE")
ALERT_TOPIC = os.environ.get("ALERT_TOPIC")
BOOTSTRAP_SERVER = os.environ.get("BOOTSTRAP_SERVER")
AWS_REGION = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION")

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(DDB_TABLE) if DDB_TABLE else None

_producer = None


def detect_anomaly(temperature, humidity):
    if temperature > 80:
        return "ALERT", f"Temperature exceeded threshold: {temperature}°C"
    if temperature < 10:
        return "ALERT", f"Temperature below threshold: {temperature}°C"
    if humidity > 90:
        return "ALERT", f"Humidity exceeded threshold: {humidity}%"
    if humidity < 20:
        return "ALERT", f"Humidity below threshold: {humidity}%"
    return "NORMAL", None


def get_producer():
    global _producer
    if _producer is not None:
        return _producer

    from aws_msk_iam_sasl_signer import MSKAuthTokenProvider
    from kafka import KafkaProducer

    class TokenProvider:
        def token(self):
            token, _ = MSKAuthTokenProvider.generate_auth_token(AWS_REGION)
            return token

    _producer = KafkaProducer(
        bootstrap_servers=[b.strip() for b in BOOTSTRAP_SERVER.split(",") if b.strip()],
        security_protocol="SASL_SSL",
        sasl_mechanism="OAUTHBEARER",
        sasl_oauth_token_provider=TokenProvider(),
        value_serializer=lambda v: json.dumps(v, ensure_ascii=False).encode("utf-8"),
        key_serializer=lambda k: k.encode("utf-8") if k else None,
        api_version=(3, 6, 0),
        request_timeout_ms=20000,
    )
    return _producer


def send_alert(payload):
    try:
        producer = get_producer()
        producer.send(ALERT_TOPIC, key=payload.get("sensorId"), value=payload)
        producer.flush(timeout=10)
        return True
    except Exception as exc:
        print(f"alert produce failed ({type(exc).__name__}): {exc}")
        return False


def save_normal(payload):
    table.put_item(Item={
        "sensorId": payload["sensorId"],
        "timestamp": payload["timestamp"],
        "temperature": str(payload["temperature"]),
        "humidity": str(payload["humidity"]),
        "location": payload.get("location", ""),
        "status": "NORMAL",
    })


def handler(event, context):
    records = []
    for partition_records in (event.get("records") or {}).values():
        records.extend(partition_records)

    print(f"Processing batch: {len(records)} messages")

    processed = 0
    alerts = 0

    for record in records:
        raw = record.get("value")
        if raw is None:
            continue

        try:
            decoded = base64.b64decode(raw).decode("utf-8")
            payload = json.loads(decoded)
        except Exception as exc:
            print(f"skip malformed record: {exc}")
            continue

        sensor_id = payload.get("sensorId", "unknown")

        try:
            temperature = float(payload.get("temperature"))
            humidity = float(payload.get("humidity"))
        except (TypeError, ValueError):
            print(f"{sensor_id}: skip - invalid temperature/humidity")
            continue

        status, reason = detect_anomaly(temperature, humidity)

        if status == "NORMAL":
            save_normal(payload)
            processed += 1
            print(f"{sensor_id}: NORMAL - temp={temperature}°C, humidity={humidity}%")
        else:
            alert_payload = dict(payload)
            alert_payload["status"] = "ALERT"
            alert_payload["alert_reason"] = reason
            send_alert(alert_payload)
            alerts += 1
            print(f"{sensor_id}: ALERT - temp={temperature}°C ({reason})")

    return {"processed": processed, "alerts": alerts, "total": len(records)}