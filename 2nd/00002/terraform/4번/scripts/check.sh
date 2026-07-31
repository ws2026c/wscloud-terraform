#!/usr/bin/env bash
# =============================================================================
# 제2과제 4) MSK  채점기준 4-1 ~ 4-5 자체 검증
#   usage: ./check.sh <비번호>     예) ./check.sh 111
# =============================================================================
set -uo pipefail

STUDENT_NO="${1:-}"
[ -z "$STUDENT_NO" ] && { echo "usage: $0 <비번호>"; exit 1; }

export AWS_DEFAULT_REGION=ap-northeast-1
TABLE=wsc2026-sensor-data
BUCKET_NAME="wsc2026-sensor-alert-bucket-${STUDENT_NO}"
CLUSTER=wsc2026-msk-cluster

PASS=0; FAIL=0
ok()  { echo -e "  \033[32m[PASS]\033[0m $1"; PASS=$((PASS+1)); }
ng()  { echo -e "  \033[31m[FAIL]\033[0m $1"; FAIL=$((FAIL+1)); }
sec() { echo; echo "── $1 ─────────────────────────────"; }

# ---------------------------------------------------------------- 4-0
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CLUSTER_ARN=$(aws kafka list-clusters --cluster-name-filter $CLUSTER \
              --query "ClusterInfoList[0].ClusterArn" --output text 2>/dev/null)
echo "ACCOUNT_ID  : $ACCOUNT_ID"
echo "CLUSTER_ARN : ${CLUSTER_ARN:-(없음)}"
echo "BUCKET_NAME : $BUCKET_NAME"

# ---------------------------------------------------------------- 4-1
sec "4-1 Resources (DynamoDB + S3)"
OUT=$(aws dynamodb describe-table --table-name $TABLE \
      --query "Table.[TableName,KeySchema[*].AttributeName]" --output text 2>&1)
echo "$OUT" | sed 's/^/      /'
echo "$OUT" | grep -q "^$TABLE" && ok "테이블 이름" || ng "테이블 없음"
echo "$OUT" | grep -qE "sensorId[[:space:]]+timestamp" && ok "Key sensorId / timestamp" || ng "KeySchema 불일치"

OUT=$(aws s3api head-bucket --bucket "$BUCKET_NAME" 2>&1)
echo "$OUT" | sed 's/^/      /'
echo "$OUT" | grep -q "$BUCKET_NAME" && ok "S3 버킷" || ng "S3 버킷 확인 실패"

# ---------------------------------------------------------------- 4-2
sec "4-2 Lambda Functions"
for fn in wsc2026-sensor-consumer wsc2026-sensor-alert-consumer; do
  OUT=$(aws lambda get-function --function-name $fn \
        --query "Configuration.[FunctionName,Runtime]" --output text 2>/dev/null)
  echo "      ${OUT:-(없음) $fn}"
  [ "$OUT" = "$(printf '%s\tpython3.14' "$fn")" ] && ok "$fn python3.14" \
    || ng "$fn 런타임 불일치 (${OUT})"
done

# ---------------------------------------------------------------- 4-3
sec "4-3 MSK Cluster Configuration"
OUT=$(aws kafka describe-cluster --cluster-arn "$CLUSTER_ARN" \
      --query "ClusterInfo.[ClusterName,State,CurrentBrokerSoftwareInfo.KafkaVersion,BrokerNodeGroupInfo.InstanceType,ClientAuthentication.Sasl.Iam.Enabled]" \
      --output text 2>&1)
echo "      $OUT"
[ "$OUT" = "$(printf '%s\tACTIVE\t3.6.0\tkafka.t3.small\tTrue' "$CLUSTER")" ] \
  && ok "$CLUSTER ACTIVE 3.6.0 kafka.t3.small True" || ng "클러스터 설정 불일치"

# ---------------------------------------------------------------- 4-4
sec "4-4 MSK Trigger Mapping"
for fn in wsc2026-sensor-consumer wsc2026-sensor-alert-consumer; do
  OUT=$(aws lambda list-event-source-mappings --function-name $fn \
        --query "EventSourceMappings[0].[State]" --output text 2>/dev/null)
  echo "      $fn : ${OUT:-(없음)}"
  [ "$OUT" = "Enabled" ] && ok "$fn Enabled" || ng "$fn 상태 ${OUT:-없음}"
done

# ---------------------------------------------------------------- 4-5-A
sec "4-5-A Data Processing Result"
OUT=$(aws dynamodb scan --table-name $TABLE --max-items 1 \
      --query "Items[0].{sensorId:sensorId.S,temperature:temperature.S,status:status.S}" \
      --output json 2>&1)
echo "$OUT" | sed 's/^/      /'
echo "$OUT" | python3 -c '
import json,sys
raw=sys.stdin.read().strip()
try:
    d=json.loads(raw)
except Exception:
    sys.exit(1)
if not isinstance(d,dict): sys.exit(1)
need=["sensorId","temperature","status"]
sys.exit(0 if all(d.get(k) for k in need) and d.get("status")=="NORMAL" else 1)
' && ok "sensorId / temperature(String) / status=NORMAL" || ng "형식 불일치 (Producer/Consumer 동작 확인 필요)"

# ---------------------------------------------------------------- 4-5-B
sec "4-5-B Producer Running"
aws dynamodb scan --table-name $TABLE --max-items 3 \
  --query "Items[*].{sensorId:sensorId.S,timestamp:timestamp.S}" --output table 2>&1 | sed 's/^/      /'
TS=$(aws dynamodb scan --table-name $TABLE --max-items 1 \
     --query "Items[0].timestamp.S" --output text 2>/dev/null)
echo "      timestamp: $TS"
echo "$TS" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\+09:00$' \
  && ok "ISO8601 KST(+09:00) 형식" || ng "timestamp 형식 불일치"

COUNT=$(aws dynamodb scan --table-name $TABLE --select COUNT --query Count --output text 2>/dev/null)
echo "      DynamoDB 총 건수: $COUNT"
[ "${COUNT:-0}" -gt 0 ] 2>/dev/null && ok "데이터 수집 중" || ng "데이터 없음"

echo
echo "==================================="
echo " PASS: $PASS   FAIL: $FAIL"
echo "==================================="
echo "※ 4-5 가 실패하면 ./diagnose.sh 로 Producer/Consumer 파이프라인을 확인하세요."
[ "$FAIL" -eq 0 ]
