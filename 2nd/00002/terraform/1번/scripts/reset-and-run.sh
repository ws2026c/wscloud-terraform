#!/usr/bin/env bash
# =============================================================================
# 채점 직전 상태 만들기
#   processed/ , error/ , DynamoDB 를 비운 뒤 test.csv 를 input/ 에 업로드한다.
#   업로드 즉시 트리거 Lambda -> Step Functions 가 실행되어
#   processed/test.csv , error/*.json , DynamoDB 5건이 생성된다.
#
#   usage: ./reset-and-run.sh <비번호> [test.csv 경로]
#
#   ※ set -e 를 쓰지 않는다. aws s3 ls / grep 은 결과가 없으면 exit 1 을 내므로
#     set -e + pipefail 조합에서는 업로드 전에 스크립트가 죽는다.
# =============================================================================
set -uo pipefail

STUDENT_NO="${1:-}"
CSV_PATH="${2:-./test.csv}"
if [ -z "$STUDENT_NO" ]; then
  echo "usage: $0 <비번호> [test.csv 경로]"
  exit 1
fi
if [ ! -f "$CSV_PATH" ]; then
  echo "test.csv 를 찾을 수 없습니다: $CSV_PATH"
  exit 1
fi

export AWS_DEFAULT_REGION=ap-southeast-1
BUCKET_NAME="wsc2026-student-score-bucket-${STUDENT_NO}"
TABLE_NAME="wsc2026-student-score"
SM_NAME="wsc2026-student-score-workflow"

if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "버킷이 없습니다: $BUCKET_NAME  (비번호 확인)"
  exit 1
fi

echo "▶ processed/ , error/ 비우기"
aws s3 rm "s3://$BUCKET_NAME/processed/" --recursive >/dev/null 2>&1
aws s3 rm "s3://$BUCKET_NAME/error/" --recursive >/dev/null 2>&1

echo "▶ input/ 안의 파일 정리 (input/ 폴더 마커는 유지)"
KEYS=$(aws s3api list-objects-v2 --bucket "$BUCKET_NAME" --prefix "input/" \
        --query "Contents[?Key!='input/'].Key" --output text 2>/dev/null)
for k in $KEYS; do
  [ "$k" = "None" ] && continue
  aws s3api delete-object --bucket "$BUCKET_NAME" --key "$k" >/dev/null 2>&1
  echo "    deleted s3://$BUCKET_NAME/$k"
done

echo "▶ input/ 폴더 마커 확인"
aws s3api put-object --bucket "$BUCKET_NAME" --key "input/" >/dev/null 2>&1

echo "▶ DynamoDB 비우기"
ITEMS=$(aws dynamodb scan --table-name "$TABLE_NAME" \
          --projection-expression "studentId,examDate" --query "Items" --output json 2>/dev/null)
if [ -n "$ITEMS" ]; then
  echo "$ITEMS" | T="$TABLE_NAME" python3 -c '
import json, os, subprocess, sys
items = json.load(sys.stdin) or []
for it in items:
    subprocess.run(["aws", "dynamodb", "delete-item",
                    "--table-name", os.environ["T"],
                    "--key", json.dumps(it)], check=False)
print(f"    deleted {len(items)} items")
'
fi

echo "▶ 실행 이력 기준점 기록"
SM_ARN=$(aws stepfunctions list-state-machines \
  --query "stateMachines[?name=='$SM_NAME'].stateMachineArn" --output text 2>/dev/null)
if [ -z "$SM_ARN" ] || [ "$SM_ARN" = "None" ]; then
  echo "  State Machine 을 찾을 수 없습니다: $SM_NAME"
  exit 1
fi
BEFORE=$(aws stepfunctions list-executions --state-machine-arn "$SM_ARN" \
          --max-results 100 --query "length(executions)" --output text 2>/dev/null)
[ "$BEFORE" = "None" ] && BEFORE=0

echo "▶ test.csv 업로드 -> 워크플로우 자동 실행"
aws s3 cp "$CSV_PATH" "s3://$BUCKET_NAME/input/test.csv" || exit 1

echo "▶ 실행 대기 (최대 90초)"
STATUS=""
for i in $(seq 1 45); do
  sleep 2
  AFTER=$(aws stepfunctions list-executions --state-machine-arn "$SM_ARN" \
            --max-results 100 --query "length(executions)" --output text 2>/dev/null)
  [ "$AFTER" = "None" ] && AFTER=0
  if [ "$AFTER" -gt "$BEFORE" ]; then
    STATUS=$(aws stepfunctions list-executions --state-machine-arn "$SM_ARN" \
              --max-results 1 --query "executions[0].status" --output text 2>/dev/null)
    echo "    execution status: $STATUS"
    [ "$STATUS" != "RUNNING" ] && break
  fi
done

if [ -z "$STATUS" ]; then
  echo
  echo "  !! Step Functions 실행이 시작되지 않았습니다. S3 -> 트리거 Lambda 구간 문제입니다."
  echo "     ./scripts/diagnose.sh $STUDENT_NO 로 원인을 확인하세요."
  exit 1
fi

echo
echo "▶ 결과"
echo "  [processed/]"; aws s3 ls "s3://$BUCKET_NAME/processed/" | sed 's/^/    /'
echo "  [error/]";     aws s3 ls "s3://$BUCKET_NAME/error/"     | sed 's/^/    /'
echo "  [dynamodb count] $(aws dynamodb scan --table-name "$TABLE_NAME" --select COUNT --query Count --output text)"
