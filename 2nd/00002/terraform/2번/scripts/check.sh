#!/usr/bin/env bash
# =============================================================================
# 제2과제 2) Real-time data analytics  채점기준 2-1 ~ 2-6 자체 검증
#   usage: ./check.sh
#   ※ ap-northeast-2 리전에서 실행
# =============================================================================
set -uo pipefail

export AWS_DEFAULT_REGION=ap-northeast-2
ALB_NAME=wsc2026-analytics-alb
TG_NAME=wsc2026-analytics-tg
EC2_NAME=wsc2026-analytics-ec2
STREAM=wsc2026-order-stream
FLINK=wsc2026-analytics-flink

PASS=0; FAIL=0
ok() { echo -e "  \033[32m[PASS]\033[0m $1"; PASS=$((PASS+1)); }
ng() { echo -e "  \033[31m[FAIL]\033[0m $1"; FAIL=$((FAIL+1)); }
sec() { echo; echo "── $1 ─────────────────────────────"; }

# ---------------------------------------------------------------- 2-0
echo "Account : $(aws sts get-caller-identity --query Account --output text)"
ALB_DNS=$(aws elbv2 describe-load-balancers --names $ALB_NAME \
            --query "LoadBalancers[0].DNSName" --output text 2>/dev/null)
EC2_ID=$(aws ec2 describe-instances \
          --filters "Name=tag:Name,Values=$EC2_NAME" "Name=instance-state-name,Values=running" \
          --query "Reservations[0].Instances[0].InstanceId" --output text 2>/dev/null)
echo "ALB_DNS : ${ALB_DNS:-(없음)}"
echo "EC2_ID  : ${EC2_ID:-(없음)}"

# ---------------------------------------------------------------- 2-1
sec "2-1 EC2 Instance"
if [ -n "$EC2_ID" ] && [ "$EC2_ID" != "None" ]; then
  TYPE=$(aws ec2 describe-instances --instance-ids "$EC2_ID" \
          --query "Reservations[0].Instances[0].InstanceType" --output text)
  SUBNET=$(aws ec2 describe-instances --instance-ids "$EC2_ID" \
            --query "Reservations[0].Instances[0].SubnetId" --output text)
  SUBNET_NAME=$(aws ec2 describe-subnets --subnet-ids "$SUBNET" \
                 --query "Subnets[0].Tags[?Key=='Name'].Value|[0]" --output text)
  echo "      type=$TYPE subnet=$SUBNET_NAME"
  [ "$SUBNET_NAME" = "analytics-priv-a" ] && ok "Subnet analytics-priv-a" || ng "Subnet 불일치 ($SUBNET_NAME)"
  [ "$TYPE" = "t3.small" ] && ok "InstanceType t3.small" || ng "InstanceType 불일치 ($TYPE)"
else
  ng "running 상태 EC2 없음 (tag:Name=$EC2_NAME)"
fi

# ---------------------------------------------------------------- 2-2
sec "2-2 ALB Resources"
LB_ARN=$(aws elbv2 describe-load-balancers --names $ALB_NAME \
          --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null)
LSN=$(aws elbv2 describe-listeners --load-balancer-arn "$LB_ARN" \
        --query "Listeners[].[Port,Protocol]" --output text 2>/dev/null)
TGO=$(aws elbv2 describe-target-groups --names $TG_NAME \
        --query "TargetGroups[].[TargetGroupName,Port]" --output text 2>/dev/null)
echo "      $LSN"
echo "      $TGO"
[ "$LSN" = "$(printf '80\tHTTP')" ] && ok "Listener 80 HTTP" || ng "Listener 불일치"
[ "$TGO" = "$(printf '%s\t5000' "$TG_NAME")" ] && ok "TargetGroup $TG_NAME 5000" || ng "TargetGroup 불일치"

HEALTH=$(aws elbv2 describe-target-health --target-group-arn \
          "$(aws elbv2 describe-target-groups --names $TG_NAME --query 'TargetGroups[0].TargetGroupArn' --output text)" \
          --query "TargetHealthDescriptions[0].TargetHealth.State" --output text 2>/dev/null)
echo "      target health: $HEALTH"
[ "$HEALTH" = "healthy" ] && ok "Target healthy" || ng "Target 상태 $HEALTH (2-5 실패 원인)"

# ---------------------------------------------------------------- 2-3-A
sec "2-3-A Kinesis Stream"
OUT=$(aws kinesis describe-stream-summary --stream-name $STREAM \
       --query "StreamDescriptionSummary.[StreamName,StreamStatus,StreamModeDetails.StreamMode]" \
       --output text 2>/dev/null)
echo "      $OUT"
[ "$OUT" = "$(printf '%s\tACTIVE\tON_DEMAND' "$STREAM")" ] && ok "$STREAM ACTIVE ON_DEMAND" || ng "불일치"

# ---------------------------------------------------------------- 2-3-B
sec "2-3-B Kinesis Data (POST /order)"
if [ -n "$ALB_DNS" ] && [ "$ALB_DNS" != "None" ]; then
  BODY=$(curl -s --max-time 10 -X POST "http://$ALB_DNS/order")
  echo "      $BODY"
  echo "$BODY" | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    sys.exit(1)
need=["event_time","order_id","price","product_name","quantity"]
missing=[k for k in need if not d.get(k)]
sys.exit(1 if missing else 0)
' && ok "5개 필드 모두 채워짐" || ng "응답 JSON 불일치"
else
  ng "ALB DNS 없음"
fi

# ---------------------------------------------------------------- 2-4
sec "2-4 Flink Application"
OUT=$(aws kinesisanalyticsv2 describe-application --application-name $FLINK \
       --query "ApplicationDetail.[ApplicationName,ApplicationStatus,RuntimeEnvironment]" \
       --output text 2>/dev/null)
echo "      $OUT"
[ "$OUT" = "$(printf '%s\tREADY\tZEPPELIN-FLINK-3_0' "$FLINK")" ] \
  && ok "$FLINK READY ZEPPELIN-FLINK-3_0" \
  || ng "불일치 (노트북을 START 했다면 RUNNING 이므로 STOP 하여 READY 로 되돌리세요)"

# ---------------------------------------------------------------- 2-5
sec "2-5 Application Health"
OUT=$(curl -s --max-time 10 "http://$ALB_DNS/health")
echo "      $OUT"
[ "$(echo "$OUT" | tr -d ' ')" = '{"status":"healthy"}' ] && ok "health OK" || ng "health 응답 불일치"

# ---------------------------------------------------------------- 2-6
sec "2-6 Systemd Service"
if [ -n "$EC2_ID" ] && [ "$EC2_ID" != "None" ]; then
  CMD_ID=$(aws ssm send-command --instance-ids "$EC2_ID" --document-name "AWS-RunShellScript" \
            --parameters '{"commands":["systemctl is-active app && systemctl is-enabled app"]}' \
            --query "Command.CommandId" --output text 2>/dev/null)
  if [ -n "$CMD_ID" ] && [ "$CMD_ID" != "None" ]; then
    sleep 5
    OUT=$(aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$EC2_ID" \
           --query "StandardOutputContent" --output text 2>/dev/null)
    echo "$OUT" | sed 's/^/      /'
    [ "$(echo "$OUT" | tr -d '\n' | tr -d ' ')" = "activeenabled" ] \
      && ok "active / enabled" || ng "systemd 상태 불일치"
  else
    ng "SSM send-command 실패 (SSM Agent 등록 대기 또는 IAM 확인)"
  fi
fi

echo
echo "==================================="
echo " PASS: $PASS   FAIL: $FAIL"
echo "==================================="
[ "$FAIL" -eq 0 ]
