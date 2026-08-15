#!/usr/bin/env bash
# =============================================================================
# 파이프라인 단계별 진단
#   S3 알림 -> 트리거 Lambda -> Step Functions -> 성적 처리 Lambda -> DynamoDB/S3
#   어느 구간에서 끊겼는지 찾아준다.
#
#   usage: ./diagnose.sh <비번호>
# =============================================================================
set -uo pipefail

STUDENT_NO="${1:-}"
[ -z "$STUDENT_NO" ] && { echo "usage: $0 <비번호>"; exit 1; }

export AWS_DEFAULT_REGION=ap-southeast-1
BUCKET_NAME="wsc2026-student-score-bucket-${STUDENT_NO}"
TABLE_NAME="wsc2026-student-score"
FUNC_NAME="wsc2026-student-score-function"
SM_NAME="wsc2026-student-score-workflow"

sec() { echo; echo "===== $1 ====================================="; }

sec "0. 리소스 존재 확인"
aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null \
  && echo "  bucket   : OK ($BUCKET_NAME)" || echo "  bucket   : 없음 ($BUCKET_NAME) <-- 비번호 확인"
aws lambda get-function --function-name "$FUNC_NAME" >/dev/null 2>&1 \
  && echo "  lambda   : OK ($FUNC_NAME)" || echo "  lambda   : 없음 ($FUNC_NAME)"
SM_ARN=$(aws stepfunctions list-state-machines \
  --query "stateMachines[?name=='$SM_NAME'].stateMachineArn" --output text 2>/dev/null)
[ -n "$SM_ARN" ] && [ "$SM_ARN" != "None" ] \
  && echo "  workflow : OK ($SM_ARN)" || echo "  workflow : 없음 ($SM_NAME)"

sec "1. S3 버킷 현재 상태"
echo "  [root]";      aws s3 ls "s3://$BUCKET_NAME/"           | sed 's/^/    /'
echo "  [input/]";    aws s3 ls "s3://$BUCKET_NAME/input/"     | sed 's/^/    /'
echo "  [processed/]"; aws s3 ls "s3://$BUCKET_NAME/processed/" | sed 's/^/    /'
echo "  [error/]";    aws s3 ls "s3://$BUCKET_NAME/error/"     | sed 's/^/    /'

sec "2. S3 Event Notification 설정"
aws s3api get-bucket-notification-configuration --bucket "$BUCKET_NAME" \
  --query "LambdaFunctionConfigurations" --output json 2>/dev/null | sed 's/^/  /'
echo "  -> LambdaFunctionArn / Events(s3:ObjectCreated:*) / prefix=input/ / suffix=.csv 확인"

sec "3. 트리거 Lambda 최근 로그"
TRIG=$(aws lambda list-functions \
        --query "Functions[?contains(FunctionName,'trigger')].FunctionName" --output text 2>/dev/null)
if [ -n "$TRIG" ] && [ "$TRIG" != "None" ]; then
  for f in $TRIG; do
    echo "  --- $f"
    aws logs tail "/aws/lambda/$f" --since 30m --format short 2>/dev/null | tail -25 | sed 's/^/    /' \
      || echo "    (로그 없음 = 한 번도 호출되지 않음)"
  done
else
  echo "  트리거 Lambda 를 찾지 못했습니다."
fi

sec "4. Step Functions 실행 이력"
if [ -n "$SM_ARN" ] && [ "$SM_ARN" != "None" ]; then
  aws stepfunctions list-executions --state-machine-arn "$SM_ARN" --max-results 5 \
    --query "executions[].[status,startDate,name]" --output table 2>/dev/null | sed 's/^/  /'

  EXEC=$(aws stepfunctions list-executions --state-machine-arn "$SM_ARN" --max-results 1 \
          --query "executions[0].executionArn" --output text 2>/dev/null)
  if [ -n "$EXEC" ] && [ "$EXEC" != "None" ]; then
    echo
    echo "  --- 최근 실행 실패 지점"
    aws stepfunctions get-execution-history --execution-arn "$EXEC" --reverse-order --max-results 12 \
      --query "events[?contains(type,'Failed')].[type,executionFailedEventDetails.cause,taskFailedEventDetails.cause,lambdaFunctionFailedEventDetails.cause]" \
      --output text 2>/dev/null | sed 's/^/    /'
    echo
    echo "  --- 최근 실행 입력/출력"
    aws stepfunctions describe-execution --execution-arn "$EXEC" \
      --query "[status,input,output,cause]" --output text 2>/dev/null | sed 's/^/    /'
  else
    echo "  실행 이력이 없습니다  <-- S3 -> 트리거 Lambda 구간이 끊긴 것"
  fi
fi

sec "5. 성적 처리 Lambda 최근 로그"
aws logs tail "/aws/lambda/$FUNC_NAME" --since 30m --format short 2>/dev/null | tail -25 | sed 's/^/  /' \
  || echo "  (로그 없음 = 한 번도 호출되지 않음)"

sec "6. DynamoDB 건수"
aws dynamodb scan --table-name "$TABLE_NAME" --select COUNT --query Count --output text 2>/dev/null | sed 's/^/  /'

sec "7. 수동 실행 테스트 (S3 알림을 건너뛰고 워크플로우 직접 실행)"
echo "  아래 명령으로 워크플로우만 따로 실행해볼 수 있습니다."
echo "  (input/test.csv 가 존재해야 합니다)"
echo
echo "  aws stepfunctions start-execution \\"
echo "    --state-machine-arn $SM_ARN \\"
echo "    --input '{\"key\":\"input/test.csv\"}'"
echo
echo "  성적 처리 Lambda 만 단독 실행:"
echo "  aws lambda invoke --function-name $FUNC_NAME \\"
echo "    --cli-binary-format raw-in-base64-out \\"
echo "    --payload '{\"key\":\"input/test.csv\"}' /dev/stdout"
