#!/usr/bin/env bash
# =============================================================================
# 4과제 파이프라인 진단
#   EC2 Producer -> MSK 토픽 -> Lambda Consumer -> DynamoDB / alert -> SNS+S3
#
#   usage: ./diagnose.sh <비번호>
# =============================================================================
set -uo pipefail

STUDENT_NO="${1:-}"
[ -z "$STUDENT_NO" ] && { echo "usage: $0 <비번호>"; exit 1; }

export AWS_DEFAULT_REGION=ap-northeast-1
CLUSTER=wsc2026-msk-cluster
TABLE=wsc2026-sensor-data
BUCKET="wsc2026-sensor-alert-bucket-${STUDENT_NO}"

sec() { echo; echo "===== $1 ====================================="; }

sec "1. MSK 클러스터"
CLUSTER_ARN=$(aws kafka list-clusters --cluster-name-filter $CLUSTER \
              --query "ClusterInfoList[0].ClusterArn" --output text 2>/dev/null)
echo "  ARN: ${CLUSTER_ARN:-없음}"
aws kafka describe-cluster --cluster-arn "$CLUSTER_ARN" \
  --query "ClusterInfo.[ClusterName,State,CurrentBrokerSoftwareInfo.KafkaVersion,BrokerNodeGroupInfo.InstanceType,NumberOfBrokerNodes,ClientAuthentication.Sasl.Iam.Enabled]" \
  --output text 2>&1 | sed 's/^/  /'
echo "  --- Bootstrap (SASL_IAM)"
aws kafka get-bootstrap-brokers --cluster-arn "$CLUSTER_ARN" \
  --query BootstrapBrokerStringSaslIam --output text 2>&1 | sed 's/^/  /'

sec "2. Producer EC2"
IID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=wsc2026-sensor-producer" \
      "Name=instance-state-name,Values=running" \
      --query "Reservations[0].Instances[0].InstanceId" --output text 2>/dev/null)
echo "  INSTANCE_ID: ${IID:-없음}"
if [ -n "$IID" ] && [ "$IID" != "None" ]; then
  echo "  --- user-data 로그 / 서비스 상태 / 토픽 목록 (SSM)"
  CMD=$(aws ssm send-command --instance-ids "$IID" --document-name AWS-RunShellScript \
    --parameters '{"commands":[
      "systemctl is-active sensor-producer",
      "systemctl is-enabled sensor-producer",
      "journalctl -u sensor-producer -n 15 --no-pager",
      "tail -40 /var/log/user-data.log",
      "BS=$(aws kafka get-bootstrap-brokers --region ap-northeast-1 --cluster-arn '"$CLUSTER_ARN"' --query BootstrapBrokerStringSaslIam --output text); /opt/kafka/bin/kafka-topics.sh --bootstrap-server $BS --command-config /opt/kafka/client.properties --describe 2>&1 | head -20"
    ]}' --query "Command.CommandId" --output text 2>/dev/null)
  if [ -n "$CMD" ] && [ "$CMD" != "None" ]; then
    sleep 12
    aws ssm get-command-invocation --command-id "$CMD" --instance-id "$IID" \
      --query "StandardOutputContent" --output text 2>&1 | sed 's/^/    /'
    aws ssm get-command-invocation --command-id "$CMD" --instance-id "$IID" \
      --query "StandardErrorContent" --output text 2>&1 | head -20 | sed 's/^/    ERR /'
  else
    echo "    SSM 명령 전송 실패 (SSM Agent 등록 대기 중일 수 있음)"
  fi
fi

sec "3. Lambda Event Source Mapping"
for fn in wsc2026-sensor-consumer wsc2026-sensor-alert-consumer; do
  echo "  --- $fn"
  aws lambda list-event-source-mappings --function-name $fn \
    --query "EventSourceMappings[].[State,Topics[0],LastProcessingResult]" --output text 2>&1 | sed 's/^/    /'
done

sec "4. Lambda 로그 (최근 30분)"
for fn in wsc2026-sensor-consumer wsc2026-sensor-alert-consumer; do
  echo "  --- $fn"
  aws logs tail "/aws/lambda/$fn" --since 30m --format short 2>&1 | tail -20 | sed 's/^/    /'
done

sec "5. DynamoDB"
echo "  건수: $(aws dynamodb scan --table-name $TABLE --select COUNT --query Count --output text 2>&1)"
aws dynamodb scan --table-name $TABLE --max-items 3 \
  --query "Items[*].{sensorId:sensorId.S,timestamp:timestamp.S,temperature:temperature.S,status:status.S}" \
  --output table 2>&1 | sed 's/^/  /'

sec "6. S3 alert 로그"
aws s3 ls "s3://$BUCKET/alert/" --recursive 2>&1 | head -10 | sed 's/^/  /'

echo
echo "===== 판독 가이드 ====================================="
echo "  2번 sensor-producer 가 active 아님 -> user-data 실패 (로그 확인)"
echo "  2번 토픽 목록에 raw/alert 없음      -> 토픽 생성 실패 (IAM 또는 부트스트랩 조회 실패)"
echo "  3번 State 가 Creating/Disabled      -> 토픽이 없거나 Lambda 권한 문제"
echo "  4번 consumer 로그 없음              -> Producer 가 메시지를 안 보내는 중"
echo "  5번 건수 0                          -> Consumer 가 DynamoDB 저장 실패 (4번 로그 확인)"
