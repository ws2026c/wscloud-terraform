#!/usr/bin/env bash
# =============================================================================
# 원샷 실행 + 진단
#   업로드 -> S3 이벤트 -> 트리거 Lambda -> Step Functions -> 결과
#   각 단계를 강제로 진행하면서 어디서 끊겼는지 즉시 출력한다.
#   S3 이벤트가 오지 않으면 워크플로우를 직접 실행해서 원인을 좁힌다.
#
#   usage: ./run-now.sh <비번호> [test.csv 경로]
#     예)  ./run-now.sh 111
# =============================================================================
set -uo pipefail

STUDENT_NO="${1:-}"
CSV_PATH="${2:-./test.csv}"
[ -z "$STUDENT_NO" ] && { echo "usage: $0 <비번호> [test.csv 경로]"; exit 1; }

export AWS_DEFAULT_REGION=ap-southeast-1
BUCKET="wsc2026-student-score-bucket-${STUDENT_NO}"
TABLE="wsc2026-student-score"
FUNC="wsc2026-student-score-function"
SM_NAME="wsc2026-student-score-workflow"

step() { echo; echo "───── $* ─────────────────────────────"; }
ok()   { echo "  [OK]   $*"; }
ng()   { echo "  [FAIL] $*"; }

# ---------------------------------------------------------------- 0
step "0. test.csv 준비"
# 원본 test.csv 는 CRLF 개행 + 끝 개행 없음 = 정확히 497 bytes.
# 채점 1-5-A 가 `497 test.csv` 를 확인하므로 바이트 단위로 동일해야 한다.
# 파일이 없거나 크기가 다르면 base64 원본에서 복원한다.
restore_csv() {
  base64 -d > "$CSV_PATH" <<'B64'
ZXhhbURhdGUsc3R1ZGVudElkLG5hbWUsY2xhc3NOYW1lLGtvcmVhbixlbmdsaXNoLG1hdGgsc2Np
ZW5jZSxoaXN0b3J5DQoyMDI2LTA1LTMwLFNUVTEwMjAs6rmA7KeA7JqwLDEtQSwxMDAsOTgsOTIs
OTcsOTYNCjIwMjYtMDUtMzAsU1RVMjAwMizsnoTsnYDshJ0sMS1FLDgyLGVpZ2h0eSw3OSw4NSw4
OA0KMjAyNi0wNS0zMCxTVFUxMjIwLOuFuOycoOuCmCwxLUIsNzgsODIsNjUsNzAsODgNCjIwMjYt
MDUtMzAsU1RVMjAwNCwsMS1FLDk1LDEwMCxBLDkwLDg4DQoyMDI2LTA1LTMwLFNUVTEyMDMs6rmA
7KO87J2ALDEtQSw4OCw4Niw4NSw5MCw4Nw0KMjAyNi0wNS0zMCxTVFUyMDAxLOydtOydgOywvSwx
LUUsODAsNzUsNzAsNzgsDQoyMDI2LTA1LTMwLFNUVTA1MTEs67CV66+87KO8LDEtQSw5NCw5Miw5
MCw5MSw5Mw0KMjAyNi0wNS0zMCxTVFU0NDQ0LOydtOq4sOykgCwxLUMsNDAsNTIsNjUsNjAsNzMN
CjIwMjYtMDUtMzAsLOq5gOyjvOybkCwxLUUsOTAsODgsODUsODcsODk=
B64
}
if [ ! -f "$CSV_PATH" ]; then
  echo "  $CSV_PATH 가 없어 원본을 복원합니다."
  restore_csv
elif [ "$(wc -c < "$CSV_PATH")" -ne 497 ]; then
  echo "  $CSV_PATH 크기가 497 이 아닙니다 ($(wc -c < "$CSV_PATH")). 원본으로 교체합니다."
  restore_csv
fi
SIZE=$(wc -c < "$CSV_PATH")
[ "$SIZE" -eq 497 ] && ok "test.csv $SIZE bytes" || ng "test.csv $SIZE bytes (497 이어야 함)"

# ---------------------------------------------------------------- 1
step "1. S3 이벤트 알림 설정 확인"
NOTI=$(aws s3api get-bucket-notification-configuration --bucket "$BUCKET" --output json 2>&1)
echo "$NOTI" | sed 's/^/    /'
if echo "$NOTI" | grep -q "LambdaFunctionArn"; then
  ok "Lambda 알림 설정 있음"
else
  ng "S3 -> Lambda 알림이 없습니다. terraform apply 가 반영되지 않았습니다."
fi

# ---------------------------------------------------------------- 2
step "2. 기존 상태 정리"
aws s3 rm "s3://$BUCKET/processed/" --recursive >/dev/null 2>&1
aws s3 rm "s3://$BUCKET/error/" --recursive >/dev/null 2>&1
KEYS=$(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "input/" \
        --query "Contents[?Key!='input/'].Key" --output text 2>/dev/null)
for k in $KEYS; do
  [ "$k" = "None" ] && continue
  aws s3api delete-object --bucket "$BUCKET" --key "$k" >/dev/null 2>&1
done
aws s3api put-object --bucket "$BUCKET" --key "input/" >/dev/null 2>&1
ITEMS=$(aws dynamodb scan --table-name "$TABLE" --projection-expression "studentId,examDate" \
          --query "Items" --output json 2>/dev/null)
[ -n "$ITEMS" ] && echo "$ITEMS" | T="$TABLE" python3 -c '
import json,os,subprocess,sys
items=json.load(sys.stdin) or []
for it in items:
    subprocess.run(["aws","dynamodb","delete-item","--table-name",os.environ["T"],"--key",json.dumps(it)],check=False)
print(f"    dynamodb 항목 {len(items)}건 삭제")
'
ok "정리 완료"

SM_ARN=$(aws stepfunctions list-state-machines \
  --query "stateMachines[?name=='$SM_NAME'].stateMachineArn" --output text 2>/dev/null)
[ -z "$SM_ARN" ] || [ "$SM_ARN" = "None" ] && { ng "State Machine 없음"; exit 1; }
BEFORE=$(aws stepfunctions list-executions --state-machine-arn "$SM_ARN" \
          --max-results 100 --query "length(executions)" --output text 2>/dev/null)
{ [ "$BEFORE" = "None" ] || [ -z "$BEFORE" ]; } && BEFORE=0

# ---------------------------------------------------------------- 3
step "3. test.csv 업로드"
UP=$(aws s3 cp "$CSV_PATH" "s3://$BUCKET/input/test.csv" 2>&1)
echo "$UP" | sed 's/^/    /'
if aws s3api head-object --bucket "$BUCKET" --key "input/test.csv" >/dev/null 2>&1; then
  ok "input/test.csv 업로드 확인"
else
  ng "업로드 실패 (권한 확인: s3:PutObject)"
  exit 1
fi

# ---------------------------------------------------------------- 4
step "4. S3 이벤트로 워크플로우가 시작되는지 대기 (30초)"
STARTED=0
for i in $(seq 1 15); do
  sleep 2
  AFTER=$(aws stepfunctions list-executions --state-machine-arn "$SM_ARN" \
            --max-results 100 --query "length(executions)" --output text 2>/dev/null)
  { [ "$AFTER" = "None" ] || [ -z "$AFTER" ]; } && AFTER=0
  if [ "$AFTER" -gt "$BEFORE" ]; then STARTED=1; ok "실행 시작됨 (${i}0초 이내)"; break; fi
done

if [ "$STARTED" -eq 0 ]; then
  ng "S3 이벤트로 실행되지 않음 -> S3/트리거 Lambda 구간 문제"
  echo
  echo "  [트리거 Lambda 목록]"
  aws lambda list-functions --query "Functions[?contains(FunctionName,'trigger')].[FunctionName,Environment.Variables.STATE_MACHINE_ARN]" \
    --output text 2>/dev/null | sed 's/^/    /'
  TRIG=$(aws lambda list-functions --query "Functions[?contains(FunctionName,'trigger')].FunctionName" --output text 2>/dev/null)
  for f in $TRIG; do
    echo "  [$f 최근 로그]"
    aws logs tail "/aws/lambda/$f" --since 10m --format short 2>&1 | tail -20 | sed 's/^/    /'
    echo "  [$f resource policy]"
    aws lambda get-policy --function-name "$f" --query Policy --output text 2>&1 | head -c 600 | sed 's/^/    /'
    echo
  done
  echo
  echo "  → 워크플로우를 직접 실행해서 나머지 구간을 검증합니다."
  aws stepfunctions start-execution --state-machine-arn "$SM_ARN" \
    --input '{"key":"input/test.csv"}' >/dev/null 2>&1
  sleep 5
fi

# ---------------------------------------------------------------- 5
step "5. 실행 결과"
for i in $(seq 1 20); do
  EXEC=$(aws stepfunctions list-executions --state-machine-arn "$SM_ARN" --max-results 1 \
          --query "executions[0].executionArn" --output text 2>/dev/null)
  ST=$(aws stepfunctions describe-execution --execution-arn "$EXEC" --query status --output text 2>/dev/null)
  [ "$ST" != "RUNNING" ] && break
  sleep 2
done
echo "  status: ${ST:-unknown}"

if [ "${ST:-}" != "SUCCEEDED" ]; then
  ng "워크플로우 실패 - 실패 지점"
  aws stepfunctions get-execution-history --execution-arn "$EXEC" --reverse-order --max-results 25 \
    --query "events[?contains(type,'Failed') || contains(type,'StateEntered')].[id,type,stateEnteredEventDetails.name,taskFailedEventDetails.error,taskFailedEventDetails.cause,executionFailedEventDetails.cause]" \
    --output text 2>/dev/null | sed 's/^/    /'
  echo
  echo "  [성적 처리 Lambda 단독 실행 결과]"
  aws lambda invoke --function-name "$FUNC" --cli-binary-format raw-in-base64-out \
    --payload '{"key":"input/test.csv"}' /tmp/out.json >/dev/null 2>&1
  cat /tmp/out.json 2>/dev/null | sed 's/^/    /'; echo
  echo "  [성적 처리 Lambda 로그]"
  aws logs tail "/aws/lambda/$FUNC" --since 10m --format short 2>&1 | tail -20 | sed 's/^/    /'
else
  ok "워크플로우 성공"
fi

# ---------------------------------------------------------------- 6
step "6. 채점 항목 최종 상태"
echo "  1-1  aws s3 ls s3://$BUCKET/"
aws s3 ls "s3://$BUCKET/" | sed 's/^/       /'
echo "  1-5-A dynamodb get-item STU1020"
aws dynamodb get-item --table-name "$TABLE" \
  --key '{"studentId":{"S":"STU1020"},"examDate":{"S":"2026-05-30"}}' \
  --query "Item.[studentId.S,average.N,grade.S]" --output text 2>/dev/null | sed 's/^/       /'
echo "  1-5-A s3 ls processed/"
aws s3 ls "s3://$BUCKET/processed/" | sed 's/^/       /'
echo "  1-5-B s3 ls error/"
aws s3 ls "s3://$BUCKET/error/" | sed 's/^/       /'
