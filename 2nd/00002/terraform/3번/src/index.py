"""WSC2026 Cloud Event Handling - 자동 복구 / 알림 Lambda

Handler 는 전 함수 공통으로 index.handler 이며,
환경변수 FUNCTION_ROLE 값으로 동작을 분기한다.

  FUNCTION_ROLE                 함수명
  --------------------------------------------------------
  SG_REMEDIATION                wsc2026-sg-remediation
  ROLE_REMEDIATION              wsc2026-role-remediation
  EC2_TERMINATE_ALERT           wsc2026-ec2-terminate-alert
  EC2_TYPE_REMEDIATION          wsc2026-ec2-type-remediation
  EC2_STOP_REMEDIATION          wsc2026-ec2-stop-remediation
  TAG_ALERT                     wsc2026-tag-alert
"""

import json
import os
from datetime import datetime, timezone

import boto3

ec2_client = boto3.client("ec2")
iam_client = boto3.client("iam")
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


# =============================================================================
# wsc2026-sg-remediation : 추가된 인바운드 규칙 삭제 + 알림
# =============================================================================
def _to_ip_permission(item):
    """CloudTrail requestParameters 의 ipPermissions.items -> revoke 용 IpPermissions"""
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

    prefixes = [{"PrefixListId": p["prefixListId"]}
                for p in (item.get("prefixListIds") or {}).get("items", []) if p.get("prefixListId")]
    if prefixes:
        perm["PrefixListIds"] = prefixes

    return perm


def sg_remediation_handler(event, context):
    sg_id = os.environ.get("SECURITY_GROUP_ID")
    detail = event.get("detail", {})
    request_params = detail.get("requestParameters") or {}

    group_id = request_params.get("groupId") or sg_id
    items = (request_params.get("ipPermissions") or {}).get("items", [])

    # 1) 이벤트에 담긴 추가 규칙을 그대로 삭제
    permissions = [_to_ip_permission(i) for i in items]
    if permissions:
        try:
            ec2_client.revoke_security_group_ingress(
                GroupId=group_id, IpPermissions=permissions)
        except Exception as exc:  # 이미 삭제된 경우 등
            print(f"revoke by event failed: {exc}")

    # 2) 남아 있는 인바운드가 있으면 모두 제거 (정상 상태 = 인바운드 0개)
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
    return {"status": "ok", "groupId": group_id}


# =============================================================================
# wsc2026-role-remediation : IAM Instance Profile 원복 + 알림
# =============================================================================
def role_remediation_handler(event, context):
    instance_id = os.environ.get("INSTANCE_ID")
    role_name = os.environ.get("ROLE_NAME")
    detail = event.get("detail", {})

    req = (detail.get("requestParameters") or {}).get("AssociateIamInstanceProfileRequest") or {}
    instance_id = req.get("InstanceId") or instance_id

    try:
        assocs = ec2_client.describe_iam_instance_profile_associations(
            Filters=[{"Name": "instance-id", "Values": [instance_id]}]
        )["IamInstanceProfileAssociations"]
        active = [a for a in assocs if a.get("State") in ("associated", "associating")]

        if active:
            ec2_client.replace_iam_instance_profile_association(
                IamInstanceProfile={"Name": role_name},
                AssociationId=active[0]["AssociationId"],
            )
        else:
            ec2_client.associate_iam_instance_profile(
                IamInstanceProfile={"Name": role_name},
                InstanceId=instance_id,
            )
    except Exception as exc:
        print(f"replace instance profile failed: {exc}")

    publish_alert(
        "ROLE_CHANGED",
        f"IAM role on instance {instance_id} was changed and restored to {role_name}",
        "RESTORED",
    )
    return {"status": "ok", "instanceId": instance_id}


# =============================================================================
# wsc2026-ec2-terminate-alert : 알림만 발송
# =============================================================================
def ec2_terminate_handler(event, context):
    detail = event.get("detail", {})
    instance_id = detail.get("instance-id", "unknown")

    publish_alert(
        "EC2_TERMINATED",
        f"Instance {instance_id} was terminated",
        "ALERT_ONLY",
    )
    return {"status": "ok", "instanceId": instance_id}


# =============================================================================
# wsc2026-ec2-type-remediation : 인스턴스 타입 원복 + 알림
# =============================================================================
def ec2_type_remediation_handler(event, context):
    instance_id = os.environ.get("INSTANCE_ID")
    original_type = os.environ.get("INSTANCE_TYPE")
    detail = event.get("detail", {})

    req = detail.get("requestParameters") or {}
    instance_id = req.get("instanceId") or instance_id

    try:
        current = ec2_client.describe_instances(InstanceIds=[instance_id])
        inst = current["Reservations"][0]["Instances"][0]

        if inst["InstanceType"] != original_type:
            if inst["State"]["Name"] != "stopped":
                ec2_client.stop_instances(InstanceIds=[instance_id])
                ec2_client.get_waiter("instance_stopped").wait(
                    InstanceIds=[instance_id],
                    WaiterConfig={"Delay": 5, "MaxAttempts": 40},
                )

            ec2_client.modify_instance_attribute(
                InstanceId=instance_id,
                InstanceType={"Value": original_type},
            )
            ec2_client.start_instances(InstanceIds=[instance_id])
    except Exception as exc:
        print(f"instance type remediation failed: {exc}")

    publish_alert(
        "EC2_TYPE_CHANGED",
        f"Instance {instance_id} type was changed and restored to {original_type}",
        "RESTORED",
    )
    return {"status": "ok", "instanceId": instance_id}


# =============================================================================
# wsc2026-ec2-stop-remediation : 중지된 인스턴스 재시작 + 알림
# =============================================================================
def ec2_stop_remediation_handler(event, context):
    detail = event.get("detail", {})
    instance_id = detail.get("instance-id") or os.environ.get("INSTANCE_ID")

    try:
        state = ec2_client.describe_instances(
            InstanceIds=[instance_id]
        )["Reservations"][0]["Instances"][0]["State"]["Name"]

        # stopping 중이면 stopped 까지 대기 후 start
        if state == "stopping":
            ec2_client.get_waiter("instance_stopped").wait(
                InstanceIds=[instance_id],
                WaiterConfig={"Delay": 5, "MaxAttempts": 40},
            )
            state = "stopped"

        if state == "stopped":
            ec2_client.start_instances(InstanceIds=[instance_id])
    except Exception as exc:
        print(f"start instance failed: {exc}")

    publish_alert(
        "EC2_STOPPED",
        f"Instance {instance_id} was stopped and has been restarted",
        "RESTORED",
    )
    return {"status": "ok", "instanceId": instance_id}


# =============================================================================
# wsc2026-tag-alert : 필수 태그 누락 복구 + 알림
# =============================================================================
def tag_alert_handler(event, context):
    instance_id = os.environ.get("INSTANCE_ID")
    required_key = os.environ.get("REQUIRED_TAG_KEY", "Name")
    required_value = os.environ.get("REQUIRED_TAG_VALUE", "wsc2026-event-ec2")

    detail = event.get("detail", {})
    resources = event.get("resources") or []
    target = instance_id
    for arn in resources:
        if ":instance/" in arn:
            target = arn.split("/")[-1]
            break

    restored = False
    try:
        tags = ec2_client.describe_tags(
            Filters=[{"Name": "resource-id", "Values": [target]}]
        )["Tags"]
        keys = {t["Key"]: t["Value"] for t in tags}

        if keys.get(required_key) != required_value:
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
    return {"status": "ok", "resource": target, "detail": detail.get("changed-tag-keys")}


# =============================================================================
# 공통 진입점 (Handler: index.handler)
# =============================================================================
HANDLERS = {
    "SG_REMEDIATION": sg_remediation_handler,
    "ROLE_REMEDIATION": role_remediation_handler,
    "EC2_TERMINATE_ALERT": ec2_terminate_handler,
    "EC2_TYPE_REMEDIATION": ec2_type_remediation_handler,
    "EC2_STOP_REMEDIATION": ec2_stop_remediation_handler,
    "TAG_ALERT": tag_alert_handler,
}


def handler(event, context):
    print(json.dumps(event, default=str))

    role = os.environ.get("FUNCTION_ROLE", "")
    func = HANDLERS.get(role)

    if func is None:
        raise RuntimeError(f"unknown FUNCTION_ROLE: {role}")

    return func(event, context)
