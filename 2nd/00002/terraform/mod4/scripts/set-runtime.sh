#!/usr/bin/env bash
# =============================================================================
# Lambda 런타임을 python3.14 로 전환 (Provider 버전 무관 우회로)
#
#   Terraform AWS Provider 가 python3.14 를 화이트리스트에 갖고 있지 않으면
#     Error: expected runtime to be one of [...], got python3.14
#   가 납니다. Provider 를 올리는 게 정석이지만, 올릴 수 없는 환경에서는
#     1) terraform.tfvars 에 lambda_runtime = "python3.13" 지정 후 apply
#     2) 이 스크립트로 런타임만 python3.14 로 변경
#   하면 됩니다. lambda.tf 에 ignore_changes = [runtime] 이 있어
#   이후 terraform apply 가 되돌리지 않습니다.
#
#   usage: ./set-runtime.sh [런타임]      기본값 python3.14
# =============================================================================
set -uo pipefail

RUNTIME="${1:-python3.14}"
export AWS_DEFAULT_REGION=ap-northeast-1

for fn in wsc2026-sensor-consumer wsc2026-sensor-alert-consumer; do
  echo "▶ $fn -> $RUNTIME"

  aws lambda update-function-configuration \
    --function-name "$fn" --runtime "$RUNTIME" \
    --query "[FunctionName,Runtime]" --output text 2>&1 | sed 's/^/    /'

  # 업데이트 반영 대기
  for i in $(seq 1 20); do
    ST=$(aws lambda get-function-configuration --function-name "$fn" \
         --query LastUpdateStatus --output text 2>/dev/null)
    [ "$ST" != "InProgress" ] && break
    sleep 3
  done
done

echo
echo "▶ 채점 4-2 확인"
for fn in wsc2026-sensor-consumer wsc2026-sensor-alert-consumer; do
  aws lambda get-function --function-name "$fn" \
    --query "Configuration.[FunctionName,Runtime]" --output text 2>&1 | sed 's/^/    /'
done
