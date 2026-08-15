"""S3 /input/ 경로에 .csv 업로드 시 Step Functions State Machine을 실행하는 트리거 Lambda."""

import json
import os
import urllib.parse

import boto3

sfn_client = boto3.client("stepfunctions")

STATE_MACHINE_ARN = os.environ.get("STATE_MACHINE_ARN")


def handler(event, context):
    if not STATE_MACHINE_ARN:
        return {"statusCode": 400, "message": "STATE_MACHINE_ARN is not configured"}

    executions = []

    for record in event.get("Records", []):
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

        # input/ 경로의 .csv 파일만 처리
        if not key.startswith("input/") or not key.lower().endswith(".csv"):
            continue

        response = sfn_client.start_execution(
            stateMachineArn=STATE_MACHINE_ARN,
            input=json.dumps({"key": key}),
        )
        executions.append(response["executionArn"])

    return {"statusCode": 200, "executions": executions}
