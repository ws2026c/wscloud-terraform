#!/usr/bin/env bash
# =============================================================================
# 제2과제 3) Cloud Event Handling  채점기준 3-0 ~ 3-5 자체 검증
#   usage: ./check.sh
#
#   ※ 채점 3-0 과 동일하게 EC2 를 중지하고 SG 에 SSH 규칙을 추가합니다(위반 유발).
#     자동 복구가 정상 동작하면 3-4 에서 running / 0 으로 돌아옵니다.
# =============================================================================
set -uo pipefail

export AWS_DEFAULT_REGION=eu-west-1
EC2_NAME=wsc2026-event-ec2
SG_NAME=wsc2026-event-sg
TOPIC=wsc2026-event-alert

PASS=0; FAIL=0
ok()  { echo -e "  \033[32m[PASS]\033[0m $1"; PASS=$((PASS+1)); }
ng()  { echo -e "  \033[31m[FAIL]\033[0m $1"; FAIL=$((FAIL+1)); }
sec() { echo; echo "── $1 ─────────────────────────────"; }

# ---------------------------------------------------------------- 3-0
sec "3-0 채점환경 준비 (위반 유발)"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$EC2_NAME" "Name=instance-state-name,Values=running,stopped" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=$SG_NAME" \
  --query "SecurityGroups[0].GroupId" --output text)

echo "  ACCOUNT_ID  : $ACCOUNT_ID"
echo "  INSTANCE_ID : $INSTANCE_ID"
echo "  SG_ID       : $SG_ID"

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
  ng "EC2 를 찾을 수 없습니다"; exit 1
fi

aws ec2 stop-instances --instance-ids "$INSTANCE_ID" >/dev/null 2>&1
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" \
  --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null 2>&1
echo "  위반 유발 완료 (EC2 중지 + SSH 인바운드 추가)"

# ---------------------------------------------------------------- 3-1
sec "3-1 SNS Topic + Lambda Functions"
OUT=$(aws sns get-topic-attributes \
      --topic-arn "arn:aws:sns:eu-west-1:${ACCOUNT_ID}:${TOPIC}" \
      --query "Attributes.TopicArn" --output text 2>/dev/null)
echo "      $OUT"
[ "$OUT" = "arn:aws:sns:eu-west-1:${ACCOUNT_ID}:${TOPIC}" ] && ok "SNS Topic" || ng "SNS Topic 없음"

for fn in wsc2026-ec2-stop-remediation wsc2026-ec2-terminate-alert \
          wsc2026-sg-remediation wsc2026-tag-alert; do
  OUT=$(aws lambda get-function --function-name "$fn" \
        --query "Configuration.[FunctionName,Runtime]" --output text 2>/dev/null)
  echo "      ${OUT:-(없음) $fn}"
  [ "$OUT" = "$(printf '%s\tpython3.12' "$fn")" ] && ok "$fn" || ng "$fn"
done

echo "      -- 문제지 추가 함수"
for fn in wsc2026-role-remediation wsc2026-ec2-type-remediation; do
  OUT=$(aws lambda get-function --function-name "$fn" \
        --query "Configuration.[FunctionName,Runtime]" --output text 2>/dev/null)
  echo "      ${OUT:-(없음) $fn}"
done

# ---------------------------------------------------------------- 3-2
sec "3-2 EventBridge Rule Targets"
declare -A EXPECT=(
  [wsc2026-ec2-stop-rule]=wsc2026-ec2-stop-remediation
  [wsc2026-ec2-terminate-rule]=wsc2026-ec2-terminate-alert
)
for rule in wsc2026-ec2-stop-rule wsc2026-ec2-terminate-rule; do
  ARN=$(aws events list-targets-by-rule --rule "$rule" --query "Targets[0].Arn" --output text 2>/dev/null)
  echo "      $rule -> $ARN"
  [ "$ARN" = "arn:aws:lambda:eu-west-1:${ACCOUNT_ID}:function:${EXPECT[$rule]}" ] \
    && ok "$rule" || ng "$rule 타겟 불일치"
done

echo "      -- 문제지 추가 Rule"
for rule in wsc2026-sg-change-rule wsc2026-role-change-rule wsc2026-ec2-type-change-rule wsc2026-tag-change-rule; do
  ARN=$(aws events list-targets-by-rule --rule "$rule" --query "Targets[0].Arn" --output text 2>/dev/null)
  echo "      $rule -> ${ARN:-(없음)}"
done

# ---------------------------------------------------------------- 3-3
sec "3-3 AWS Config Rules"
OUT=$(aws configservice describe-config-rules \
      --config-rule-names wsc2026-sg-ssh-rule wsc2026-required-tags-rule \
      --query "ConfigRules[*].[ConfigRuleName,ConfigRuleState]" --output text 2>/dev/null)
echo "$OUT" | sed 's/^/      /'
echo "$OUT" | grep -q "wsc2026-sg-ssh-rule.*ACTIVE"      && ok "wsc2026-sg-ssh-rule ACTIVE"      || ng "wsc2026-sg-ssh-rule"
echo "$OUT" | grep -q "wsc2026-required-tags-rule.*ACTIVE" && ok "wsc2026-required-tags-rule ACTIVE" || ng "wsc2026-required-tags-rule"

# ---------------------------------------------------------------- 3-4
sec "3-4 자동 복구 결과 (최대 5분 대기)"
STATE=""; CNT=""
for i in $(seq 1 30); do
  sleep 10
  STATE=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
           --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null)
  CNT=$(aws ec2 describe-security-groups --group-ids "$SG_ID" \
         --query "SecurityGroups[0].IpPermissions | length(@)" --output text 2>/dev/null)
  echo "      [$((i*10))s] state=$STATE inbound=$CNT"
  [ "$STATE" = "running" ] && [ "$CNT" = "0" ] && break
done
[ "$STATE" = "running" ] && ok "EC2 State running" || ng "EC2 State $STATE (기대: running)"
[ "$CNT" = "0" ] && ok "SG Inbound Count 0" || ng "SG Inbound Count $CNT (기대: 0)"

# ---------------------------------------------------------------- 3-5
sec "3-5 required-tags 규칙 위반 리소스"
OUT=$(aws configservice get-compliance-details-by-config-rule \
      --config-rule-name wsc2026-required-tags-rule --compliance-types NON_COMPLIANT \
      --query "EvaluationResults[0].EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId" \
      --output text 2>/dev/null)
echo "      ${OUT:-None}"
[ -z "$OUT" ] || [ "$OUT" = "None" ] && ok "NON_COMPLIANT 없음" || ng "위반 리소스: $OUT"

echo
echo "==================================="
echo " PASS: $PASS   FAIL: $FAIL"
echo "==================================="
echo "※ Config 규칙은 최초 평가까지 몇 분 걸립니다. 3-3/3-5 가 실패하면 5분 뒤 다시 실행하세요."
[ "$FAIL" -eq 0 ]
