#!/usr/bin/env bash
# =============================================================================
# 채점기준 1-1 ~ 1-5-B 자체 검증 스크립트 (CloudShell 에서 실행)
#   usage: ./check.sh <비번호>     예) ./check.sh 103
# =============================================================================
set -uo pipefail

STUDENT_NO="${1:-}"
if [ -z "$STUDENT_NO" ]; then
  echo "usage: $0 <비번호>   예) $0 103"
  exit 1
fi

export AWS_DEFAULT_REGION=ap-southeast-1
BUCKET_NAME="wsc2026-student-score-bucket-${STUDENT_NO}"
TABLE_NAME="wsc2026-student-score"
FUNC_NAME="wsc2026-student-score-function"
SM_NAME="wsc2026-student-score-workflow"

PASS=0
FAIL=0
ok()   { echo -e "  \033[32m[PASS]\033[0m $1"; PASS=$((PASS + 1)); }
ng()   { echo -e "  \033[31m[FAIL]\033[0m $1"; FAIL=$((FAIL + 1)); }
head_() { echo; echo "── $1 ─────────────────────────────"; }

echo "Account : $(aws sts get-caller-identity --query Account --output text)"
echo "Bucket  : $BUCKET_NAME"

# ---------------------------------------------------------------- 1-1
head_ "1-1 S3 Bucket + Folder Structure"
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  OUT=$(aws s3 ls "s3://$BUCKET_NAME/")
  echo "$OUT" | sed 's/^/      /'
  PRE=$(echo "$OUT" | awk '$1=="PRE"{print $2}' | sort | tr '\n' ' ')
  if [ "$PRE" = "error/ input/ processed/ " ]; then
    ok "PRE error/ input/ processed/"
  else
    ng "prefix 불일치 -> [$PRE]  (processed//error/ 는 워크플로우를 1회 실행해야 생성됩니다)"
  fi
else
  ng "버킷 없음: $BUCKET_NAME  (비번호 확인!)"
fi

# ---------------------------------------------------------------- 1-2
head_ "1-2 DynamoDB Table + Key Schema"
OUT=$(aws dynamodb describe-table --table-name "$TABLE_NAME" \
        --query "Table.[TableName,KeySchema]" --output json 2>/dev/null)
echo "$OUT" | sed 's/^/      /'
if echo "$OUT" | tr -d ' \n' | grep -q '"studentId","KeyType":"HASH"' &&
   echo "$OUT" | tr -d ' \n' | grep -q '"examDate","KeyType":"RANGE"'; then
  ok "studentId(HASH) / examDate(RANGE)"
else
  ng "KeySchema 불일치"
fi

# ---------------------------------------------------------------- 1-3
head_ "1-3 Lambda Function + Runtime + Env"
OUT=$(aws lambda get-function-configuration --function-name "$FUNC_NAME" \
        --query "[FunctionName,Runtime,Environment.Variables]" --output json 2>/dev/null)
if [ -z "$OUT" ]; then
  ng "함수 없음: $FUNC_NAME"
else
  echo "$OUT" | sed 's/^/      /'
  FLAT=$(echo "$OUT" | tr -d ' \n')
  [[ "$FLAT" == *"\"$FUNC_NAME\""* ]]              && ok "FunctionName" || ng "FunctionName"
  [[ "$FLAT" == *'"python3.12"'* ]]                && ok "Runtime python3.12" || ng "Runtime"
  [[ "$FLAT" == *"\"S3_BUCKET\":\"$BUCKET_NAME\""* ]] && ok "S3_BUCKET" || ng "S3_BUCKET 값 불일치"
  [[ "$FLAT" == *"\"DDB_TABLE\":\"$TABLE_NAME\""* ]]  && ok "DDB_TABLE" || ng "DDB_TABLE 값 불일치"
fi

# ---------------------------------------------------------------- 1-4
head_ "1-4 Step Functions State Machine"
SM_ARN=$(aws stepfunctions list-state-machines \
          --query "stateMachines[?name=='$SM_NAME'].stateMachineArn" --output text)
if [ -n "$SM_ARN" ]; then
  OUT=$(aws stepfunctions describe-state-machine --state-machine-arn "$SM_ARN" \
          --query "[name,type]" --output text)
  echo "      $OUT"
  [ "$OUT" = "$(printf '%s\tSTANDARD' "$SM_NAME")" ] && ok "$SM_NAME STANDARD" || ng "name/type 불일치"
else
  ng "State Machine 없음: $SM_NAME"
fi

# ---------------------------------------------------------------- 1-5-A
head_ "1-5-A Workflow Result (Normal)"
OUT=$(aws dynamodb get-item --table-name "$TABLE_NAME" \
        --key '{"studentId":{"S":"STU1020"},"examDate":{"S":"2026-05-30"}}' \
        --query "Item.[studentId.S,average.N,grade.S]" --output text 2>/dev/null)
echo "      ${OUT:-(항목 없음)}"
[ "$OUT" = "$(printf 'STU1020\t96.6\tA')" ] && ok "STU1020 96.6 A" || ng "DynamoDB 값 불일치 (기대: STU1020 96.6 A)"

OUT=$(aws s3 ls "s3://$BUCKET_NAME/processed/")
echo "$OUT" | sed 's/^/      /'
CNT=$(echo "$OUT" | grep -c . )
if [ "$(echo "$OUT" | awk '{print $4}' | tr -d ' \n')" = "test.csv" ] && [ "$CNT" = "1" ]; then
  ok "processed/ 에 test.csv 만 존재"
else
  ng "processed/ 출력이 test.csv 한 줄이 아님 (0-byte 폴더 마커가 있으면 오답)"
fi

# ---------------------------------------------------------------- 1-5-B
head_ "1-5-B Workflow Result (Error)"
OUT=$(aws s3 ls "s3://$BUCKET_NAME/error/")
echo "$OUT" | sed 's/^/      /'
NAMES=$(echo "$OUT" | awk '{print $4}' | grep -o '_[A-Za-z0-9]*\.json$' | sed 's/^_//;s/\.json$//' | sort | tr '\n' ' ')
CNT=$(echo "$OUT" | grep -c .)
if [ "$NAMES" = "STU2001 STU2002 STU2004 unknown " ] && [ "$CNT" = "4" ]; then
  ok "error json 4개 (STU2001 / STU2002 / STU2004 / unknown)"
else
  ng "error/ 출력 불일치 -> [$NAMES] (총 $CNT 줄, 0-byte 폴더 마커가 있으면 오답)"
fi

echo
echo "==================================="
echo " PASS: $PASS   FAIL: $FAIL"
echo "==================================="
[ "$FAIL" -eq 0 ]
