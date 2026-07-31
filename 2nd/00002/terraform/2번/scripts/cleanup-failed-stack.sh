#!/usr/bin/env bash
# =============================================================================
# ROLLBACK_COMPLETE 상태로 남은 CloudFormation 스택 정리
#   ROLLBACK_COMPLETE 스택은 업데이트가 불가능해서, 지우지 않으면
#   다음 terraform apply 도 같은 자리에서 실패한다.
#
#   usage: ./cleanup-failed-stack.sh
# =============================================================================
set -uo pipefail

export AWS_DEFAULT_REGION=ap-northeast-2
STACK=wsc2026-analytics-flink-studio

STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK" \
          --query "Stacks[0].StackStatus" --output text 2>/dev/null)

if [ -z "$STATUS" ] || [ "$STATUS" = "None" ]; then
  echo "스택 없음 - 정리할 것이 없습니다."
else
  echo "현재 상태: $STATUS -> 삭제"
  aws cloudformation delete-stack --stack-name "$STACK"
  aws cloudformation wait stack-delete-complete --stack-name "$STACK" 2>/dev/null
  echo "삭제 완료"
fi

echo
echo "Terraform state 에 남아 있으면 제거하세요:"
echo "  terraform state list | grep cloudformation"
echo "  terraform state rm aws_cloudformation_stack.flink_studio"
