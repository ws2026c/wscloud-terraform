#!/bin/bash
set -x
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

REGION="${region}"
CLUSTER_ARN="${cluster_arn}"
TOPIC_RAW="${topic_raw}"
TOPIC_ALERT="${topic_alert}"
ARTIFACT_BUCKET="${artifact_bucket}"
BUILD_LAYER="${build_layer}"
CONSUMER_FN="${consumer_function_name}"
BOOTSTRAP_MODE="${producer_bootstrap}"

echo "=== 1. 패키지 설치 ==="
dnf -y install java-17-amazon-corretto-headless tar gzip unzip python3-pip

echo "=== 2. Kafka CLI 설치 ==="
mkdir -p /opt/kafka
cd /opt/kafka
for i in 1 2 3; do
  curl -fsSL -o kafka.tgz "https://archive.apache.org/dist/kafka/${kafka_version}/kafka_2.13-${kafka_version}.tgz" && break
  sleep 10
done
tar -xzf kafka.tgz --strip-components=1
rm -f kafka.tgz

# IAM 접속이 필요할 때를 대비한 라이브러리 (진단용으로도 유용)
for i in 1 2 3; do
  curl -fsSL -o /opt/kafka/libs/aws-msk-iam-auth.jar \
    "https://github.com/aws/aws-msk-iam-auth/releases/download/v2.2.0/aws-msk-iam-auth-2.2.0-all.jar" && break
  sleep 10
done

cat > /opt/kafka/client-iam.properties <<'PROPS'
security.protocol=SASL_SSL
sasl.mechanism=AWS_MSK_IAM
sasl.jaas.config=software.amazon.msk.auth.iam.IAMLoginModule required;
sasl.client.callback.handler.class=software.amazon.msk.auth.iam.IAMClientCallbackHandler
PROPS

cat > /opt/kafka/client-tls.properties <<'PROPS'
security.protocol=SSL
PROPS

echo "=== 3. Bootstrap Broker 조회 ==="
case "$BOOTSTRAP_MODE" in
  iam)       QUERY=BootstrapBrokerStringSaslIam; CONFIG="--command-config /opt/kafka/client-iam.properties" ;;
  tls)       QUERY=BootstrapBrokerStringTls;     CONFIG="--command-config /opt/kafka/client-tls.properties" ;;
  *)         QUERY=BootstrapBrokerString;        CONFIG="" ;;
esac

BOOTSTRAP=""
for i in $(seq 1 30); do
  BOOTSTRAP=$(aws kafka get-bootstrap-brokers --region "$REGION" \
    --cluster-arn "$CLUSTER_ARN" --query "$QUERY" --output text 2>/dev/null)
  [ -n "$BOOTSTRAP" ] && [ "$BOOTSTRAP" != "None" ] && break
  echo "waiting for bootstrap brokers... ($i)"
  sleep 20
done
echo "BOOTSTRAP_MODE=$BOOTSTRAP_MODE"
echo "BOOTSTRAP=$BOOTSTRAP"

# 전체 부트스트랩 정보를 기록해 둔다 (진단용)
aws kafka get-bootstrap-brokers --region "$REGION" --cluster-arn "$CLUSTER_ARN" \
  > /opt/kafka/bootstrap.json 2>&1
cat /opt/kafka/bootstrap.json

echo "=== 4. 토픽 생성 ==="
create_topic() {
  local name=$1 parts=$2 rf=$3
  for i in 1 2 3 4 5; do
    /opt/kafka/bin/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" $CONFIG \
      --create --if-not-exists --topic "$name" \
      --partitions "$parts" --replication-factor "$rf" && return 0
    echo "retry create topic $name ($i)"
    sleep 15
  done
  return 1
}
create_topic "$TOPIC_RAW" 3 2
create_topic "$TOPIC_ALERT" 1 2

/opt/kafka/bin/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" $CONFIG --describe

echo "=== 5. Producer 애플리케이션 배치 ==="
mkdir -p /opt/app
aws s3 cp "s3://$ARTIFACT_BUCKET/app" /opt/app/app --region "$REGION"
chmod +x /opt/app/app

cat > /etc/systemd/system/sensor-producer.service <<UNIT
[Unit]
Description=WSC2026 Sensor Producer
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/app
Environment="BOOTSTRAP_SERVERS=$BOOTSTRAP"
Environment="TOPIC_RAW=$TOPIC_RAW"
Environment="AWS_REGION=$REGION"
Environment="AWS_DEFAULT_REGION=$REGION"
ExecStart=/opt/app/app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable sensor-producer
systemctl restart sensor-producer
sleep 10
systemctl is-active sensor-producer
journalctl -u sensor-producer -n 30 --no-pager

echo "=== 6. 토픽에 실제로 쌓이는지 확인 ==="
timeout 20 /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server "$BOOTSTRAP" $CONFIG \
  --topic "$TOPIC_RAW" --from-beginning --max-messages 3 || echo "(메시지 확인 실패)"

echo "=== 7. Lambda kafka 레이어 빌드 (옵션) ==="
if [ "$BUILD_LAYER" = "true" ]; then
  (
    set -e
    rm -rf /tmp/layer && mkdir -p /tmp/layer/python
    pip3 install --target /tmp/layer/python kafka-python-ng aws-msk-iam-sasl-signer-python \
      || pip3 install --target /tmp/layer/python kafka-python aws-msk-iam-sasl-signer-python
    cd /tmp/layer && zip -qr /tmp/kafka-layer.zip python
    aws s3 cp /tmp/kafka-layer.zip "s3://$ARTIFACT_BUCKET/kafka-layer.zip" --region "$REGION"
    LAYER_ARN=$(aws lambda publish-layer-version --region "$REGION" \
      --layer-name wsc2026-kafka-layer \
      --content "S3Bucket=$ARTIFACT_BUCKET,S3Key=kafka-layer.zip" \
      --query LayerVersionArn --output text)
    echo "LAYER_ARN=$LAYER_ARN"
    aws lambda update-function-configuration --region "$REGION" \
      --function-name "$CONSUMER_FN" --layers "$LAYER_ARN"
  ) || echo "레이어 빌드 실패 - DynamoDB 저장 동작에는 영향 없음"
fi

echo "=== user-data 완료 ==="
