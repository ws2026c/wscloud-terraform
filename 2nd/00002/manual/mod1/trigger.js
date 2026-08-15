import json, os, urllib.parse, boto3
sfn = boto3.client("stepfunctions")
ARN = os.environ["STATE_MACHINE_ARN"]

def handler(event, context):
    for r in event.get("Records", []):
        key = urllib.parse.unquote_plus(r["s3"]["object"]["key"])
        if key.startswith("input/") and key.endswith(".csv"):
            sfn.start_execution(stateMachineArn=ARN, input=json.dumps({"key": key}))
    return {"statusCode": 200}