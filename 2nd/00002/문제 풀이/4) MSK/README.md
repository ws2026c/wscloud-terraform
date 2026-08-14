# 전국대회 2과제 00002

## MSK - region : **ap-northeast-1 (도쿄)**

**1 VPC**

- VPC 과제지 요구사항대로 생성

**2 보안 그룹 3개**

### `msk-sg`
- 인바운드 1: TCP **9092** ← 소스 `ec2-sg`
- 인바운드 2: TCP **9098** ← 소스 `lambda-sg`
- 인바운드 3: **모든 TCP** ← 소스 `msk-sg`

### `ec2-sg`
- 인바운드 없음 / 아웃바운드 전체 허용(기본)

### `lambda-sg`
- 인바운드 없음 / 아웃바운드 전체 허용(기본)

---

**3 MSK 클러스터**

**MSK → 클러스터 생성 → 사용자 지정 생성**

- 영역: 2 / 영역당 브로커: 1 (총 2개)
- 스토리지: 기본
- 네트워킹: msk-vpc / msk-priv-a, msk-priv-d / 보안 그룹 `msk-sg`
- 액세스 제어 방법:
  - IAM 역할 기반 인증
  - 인증되지 않은 액세스
- 암호화(전송 중): **TLS 및 일반 텍스트(TLS_PLAINTEXT)** 선택
- 생성

---

**4 DynamoDB + S3 + SNS**

- DynamoDB와 S3를 과제지 요구사항대로 설정
- sns: 표준 주제 아무 이름 (예: `wsc2026-sensor-alert-topic`)

---

**5 IAM 역할 2개**

### `wsc2026-msk-ec2-role`
- 신뢰: EC2
- 정책: `AmazonSSMManagedInstanceCore`, `AmazonMSKFullAccess`, `AmazonS3ReadOnlyAccess`

### `wsc2026-msk-lambda-role`
- 신뢰: Lambda
- 정책: `AWSLambdaMSKExecutionRole`, `AmazonDynamoDBFullAccess`, `AmazonSNSFullAccess`, `AmazonS3FullAccess`
- 인라인 정책 추가

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "kafka-cluster:Connect", "kafka-cluster:DescribeCluster",
      "kafka-cluster:ReadData", "kafka-cluster:WriteData",
      "kafka-cluster:DescribeTopic",
      "kafka-cluster:DescribeGroup", "kafka-cluster:AlterGroup"
    ],
    "Resource": "*"
  }]
}
```

---

**6 Lambda 2개**

공통: **Python 3.14** / 역할 `wsc2026-msk-lambda-role` / 파일명 `index.py` / 핸들러 `index.handler` / 제한시간 1분

### `wsc2026-sensor-consumer`
- 코드: github의 wsc2026-sensor-consumer.py
- 환경 변수: `DDB_TABLE`=`wsc2026-sensor-data`, `ALERT_TOPIC`=`wsc2026-sensor-alert`, `BOOTSTRAP_SERVER`=(클러스터 완성 후 채우기)

### `wsc2026-sensor-alert-consumer`
- 코드: github의 wsc2026-sensor-alert-consumer
- 환경 변수: `SNS_TOPIC_ARN`=SNS ARN, `S3_BUCKET`=`wsc2026-sensor-alert-bucket-<비번호>`

---

**7 EC2 설정**

- MSK 클러스터 → 클라이언트 정보 보기 → **일반 텍스트(9092)** 엔드포인트 복사 = `<부트스트랩>`

- EC2 -> 인스턴스 시작
- 이름: `wsc2026-sensor-producer` / t3.small
- 서브넷 **msk-priv-a** / 퍼블릭 IP 비활성 / SG `ec2-sg` / IAM `wsc2026-msk-ec2-role`

SSM 통해 접속해서: 

```bash
sudo dnf -y install java-17-amazon-corretto-headless
cd /opt && sudo curl -O https://archive.apache.org/dist/kafka/3.6.0/kafka_2.13-3.6.0.tgz
sudo tar -xzf kafka_2.13-3.6.0.tgz && sudo mv kafka_2.13-3.6.0 kafka
```
```bash
B=<부트스트랩 엔드포인트>
/opt/kafka/bin/kafka-topics.sh --bootstrap-server $B --create --topic wsc2026-sensor-raw --partitions 3 --replication-factor 2
/opt/kafka/bin/kafka-topics.sh --bootstrap-server $B --create --topic wsc2026-sensor-alert --partitions 1 --replication-factor 2
```
```bash
sudo mkdir -p /opt/app
sudo aws s3 cp s3://<임시버킷>/app /opt/app/app
sudo chmod +x /opt/app/app
```
- s3가 아니라 scp 사용해도 무관
```bash
sudo tee /etc/systemd/system/sensor-producer.service <<EOF
[Unit]
After=network-online.target
[Service]
Environment="BOOTSTRAP_SERVERS=$B"
Environment="TOPIC_RAW=wsc2026-sensor-raw"
ExecStart=/opt/app/app
Restart=always
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now sensor-producer
```
- systemd service 잘 띄워졌는지 확인은\
journalctl -u sensor-producer -n 5 -> SENSOR-00x 로그 나옴 성공

---

**8 Lambda MSK 트리거 연결**

`wsc2026-sensor-consumer` 함수 → 환경변수 `BOOTSTRAP_SERVER` 를 IAM(9098) 엔드포인트로 채우기(msk 클러스터 -> 클라이언트 정보 보기 -> IAM Endpoint)

- 함수 → 트리거 추가 → MSK\
 클러스터: wsc2026-msk-cluster

  - 함수 : `wsc2026-sensor-consumer`\
    토픽: `wsc2026-sensor-raw`


  - 함수 : `wsc2026-sensor-alert-consumer`\
  토픽: `wsc2026-sensor-alert`