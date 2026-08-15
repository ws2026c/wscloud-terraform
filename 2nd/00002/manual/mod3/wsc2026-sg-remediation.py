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


def to_ip_permission(item):
    """CloudTrail requestParameters.ipPermissions.items -> revoke용 IpPermissions 형식"""
    perm = {"IpProtocol": item.get("ipProtocol")}

    if item.get("fromPort") is not None:
        perm["FromPort"] = item["fromPort"]
    if item.get("toPort") is not None:
        perm["ToPort"] = item["toPort"]

    v4 = [{"CidrIp": r["cidrIp"]}
          for r in (item.get("ipRanges") or {}).get("items", []) if r.get("cidrIp")]
    if v4:
        perm["IpRanges"] = v4

    v6 = [{"CidrIpv6": r["cidrIpv6"]}
          for r in (item.get("ipv6Ranges") or {}).get("items", []) if r.get("cidrIpv6")]
    if v6:
        perm["Ipv6Ranges"] = v6

    pairs = [{"GroupId": g["groupId"]}
             for g in (item.get("groups") or {}).get("items", []) if g.get("groupId")]
    if pairs:
        perm["UserIdGroupPairs"] = pairs

    return perm


def handler(event, context):
    sg_id = os.environ.get("SECURITY_GROUP_ID")
    detail = event.get("detail", {})
    request_params = detail.get("requestParameters") or {}

    group_id = request_params.get("groupId") or sg_id

    items = (request_params.get("ipPermissions") or {}).get("items", [])
    permissions = [to_ip_permission(i) for i in items]
    if permissions:
        try:
            ec2_client.revoke_security_group_ingress(
                GroupId=group_id, IpPermissions=permissions)
        except Exception as exc:
            print(f"revoke by event failed: {exc}")

    try:
        groups = ec2_client.describe_security_groups(GroupIds=[group_id])["SecurityGroups"]
        remaining = groups[0].get("IpPermissions", []) if groups else []
        if remaining:
            ec2_client.revoke_security_group_ingress(
                GroupId=group_id, IpPermissions=remaining)
    except Exception as exc:
        print(f"revoke remaining failed: {exc}")

    publish_alert(
        "SG_INBOUND_ADDED",
        f"Unauthorized inbound rule removed from {group_id}",
        "RESTORED",
    )
    return {"statusCode": 200}