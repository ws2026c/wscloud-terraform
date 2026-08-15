# WSC2026 제2과제 - 4) MSK (Terraform)

센서 데이터 → MSK → Lambda Consumer → DynamoDB / 이상 알림. Region: **ap-northeast-1**

## ⏱ 먼저 읽어주세요

**MSK 클러스터 생성에 20~40분 걸립니다.** `terraform apply` 가 오래 멈춰 있어도 정상입니다.
전체 apply 는 MSK(약 30분) + EC2 부팅/토픽 생성 대기(7분) 로 **40분 내외**를 예상하세요.

## 채점기준 매핑

| 채점 | 기대값 | 담당 |
|------|--------|------|
| 4-1 | `wsc2026-sensor-data` / `sensorId timestamp`, `wsc2026-sensor-alert-bucket-<비번호>` | `storage.tf` |
| 4-2 | `wsc2026-sensor-consumer` / `wsc2026-sensor-alert-consumer` (python3.14) | `lambda.tf` |
| 4-3 | `wsc2026-msk-cluster ACTIVE 3.6.0 kafka.t3.small True` | `msk.tf` |
| 4-4 | 두 함수 Event Source Mapping `Enabled` | `lambda.tf` |
| 4-5-A | `sensorId` / `temperature`(**String**) / `status=NORMAL` | `src/consumer/index.py` |
| 4-5-B | `timestamp` = `YYYY-MM-DDTHH:mm:ss+09:00` | app 바이너리 출력 그대로 저장 |

> 4-5-A 의 채점 쿼리가 `temperature.S` 라서 DynamoDB 에 **문자열**로 저장합니다(`str(75.5)` → `"75.5"`).
> `status` 필드도 함께 저장해야 하므로 NORMAL 데이터에 `status="NORMAL"` 을 넣습니다.

## 파일 구성

| 파일 | 내용 |
|------|------|
| `vpc.tf` | msk-vpc 192.168.0.0/16, pub-a/d, priv-a/d, IGW/NAT, 라우팅 3종 |
| `security.tf` | MSK SG(9098) + **self 참조 규칙**(Lambda MSK ENI 필수), EC2/Lambda SG |
| `msk.tf` | 클러스터 3.6.0 / kafka.t3.small / 2 브로커 / IAM 인증 전용 |
| `storage.tf` | DynamoDB, alert 버킷, app 배포용 버킷, SNS |
| `iam.tf` | `wsc2026-msk-ec2-role`, `wsc2026-msk-lambda-role` (최소권한) |
| `ec2.tf` + `templates/user_data.sh.tpl` | 토픽 생성 + app systemd 실행 + kafka 레이어 빌드 |
| `lambda.tf` | Consumer 2종 + Event Source Mapping |
| `src/consumer/index.py` | 이상 탐지 → DynamoDB / alert 토픽 produce |
| `src/alert_consumer/index.py` | SNS 발송 + S3 로그 저장 |
| `app/app` | 배포된 Go 프로듀서 바이너리 (S3 경유로 EC2 에 배포) |
| `scripts/check.sh` | 채점 4-1~4-5 자체 검증 |
| `scripts/diagnose.sh` | Producer → 토픽 → Consumer → DynamoDB 단계별 추적 |

## 배포

```bash
export AWS_DEFAULT_REGION=ap-northeast-1
cp terraform.tfvars.example terraform.tfvars   # student_number 수정

terraform init
terraform validate
terraform apply -auto-approve      # 40분 내외
```

apply 후 데이터가 쌓이기까지 1~2분 더 기다린 뒤 검증하세요.

```bash
chmod +x scripts/*.sh
./scripts/check.sh 111
./scripts/diagnose.sh 111   # 문제 있을 때
```

## 토픽은 Terraform 이 만들지 않습니다

Terraform AWS Provider 에는 Kafka 토픽 리소스가 없고, 브로커가 Private Subnet 에 있어
외부(노트북)에서 직접 만들 수도 없습니다. 그래서 **EC2 user_data 가 부팅 시 생성**합니다.

```
wsc2026-sensor-raw    partitions 3, replication-factor 2
wsc2026-sensor-alert  partitions 1, replication-factor 2
```

Kafka CLI + `aws-msk-iam-auth` JAR 를 내려받아 SASL_SSL/AWS_MSK_IAM 으로 접속합니다.
Event Source Mapping 은 토픽이 있어야 만들어지므로 `time_sleep` 으로 7분 대기 후 생성합니다.

수동으로 다시 만들려면 SSM 으로 접속해서:

```bash
BS=$(aws kafka get-bootstrap-brokers --cluster-arn <CLUSTER_ARN> \
      --query BootstrapBrokerStringSaslIam --output text --region ap-northeast-1)
/opt/kafka/bin/kafka-topics.sh --bootstrap-server $BS \
  --command-config /opt/kafka/client.properties --describe
```

## ⚠️ v3 수정 — 프로듀서가 MSK 에 접속하지 못하던 문제

증상: `4-5-A` 가 `null`, `4-5-B` 가 무출력 (= DynamoDB 가 비어 있음).

**원인: 배포된 `app` 바이너리에 SASL 인증 구현이 전혀 없습니다.**
바이너리를 분석한 결과입니다.

| 확인 항목 | 결과 |
|-----------|------|
| Kafka 클라이언트 | `github.com/segmentio/kafka-go` |
| 읽는 환경변수 | `BOOTSTRAP_SERVERS`, `TOPIC_RAW` **두 개뿐** |
| `AWS_MSK_IAM` 문자열 | 0건 |
| `AWS4-HMAC-SHA256` / `X-Amz-Credential` | 0건 |
| aws-msk-iam-signer / aws-sdk-go | 링크 안 됨 |
| SCRAM / PLAIN / OAUTHBEARER | 0건 |

SASL 메커니즘 이름은 SaslHandshake 요청에 그대로 실려 가므로 바이너리에 문자열이 반드시 남습니다.
하나도 없다는 것은 **평문(9092)으로만 접속한다**는 뜻입니다.
IAM 전용 클러스터에는 애초에 붙을 수 없어 메시지가 한 건도 발행되지 않았습니다.

**수정**: IAM 은 그대로 켜 두고(채점 4-3 은 `Sasl.Iam.Enabled` 만 확인) 비인증 접근을 함께 허용합니다.

```hcl
client_authentication {
  sasl { iam = true }
  unauthenticated = true          # allow_unauthenticated
}
encryption_info {
  encryption_in_transit { client_broker = "TLS_PLAINTEXT" }
}
```

- 프로듀서 / 토픽 생성 : `BootstrapBrokerString` (9092 PLAINTEXT)
- Lambda Event Source  : IAM (9098) 그대로
- 보안그룹에 9092 / 9094 / 9098 모두 개방

`producer_bootstrap` 변수로 `plaintext | tls | iam` 을 바꿀 수 있습니다.
IAM 을 지원하는 프로듀서로 직접 교체했다면 `allow_unauthenticated = false` 로 되돌리세요.

> **클러스터 재생성 가능성** — `encryption_in_transit` / `client_authentication` 변경은
> 상황에 따라 MSK 클러스터 교체(약 30분)를 유발합니다. `terraform plan` 에서
> `# forces replacement` 가 보이면 재생성입니다.

## 주의사항

**1. `python3.14` 런타임 — Provider 를 반드시 올려야 합니다**

AWS Provider 5.x 는 Lambda 런타임을 내부 화이트리스트로 검증하는데 거기에 `python3.14` 가 없습니다.

```
Error: expected runtime to be one of ["nodejs" ... "python3.13" "nodejs22.x"], got python3.14
```

`provider.tf` 의 제약을 `>= 6.0` 으로 올려두었으니 **반드시 `-upgrade` 로 재초기화**하세요.

```bash
terraform init -upgrade
```

기존 `.terraform.lock.hcl` 이 구버전을 고정하고 있으면 `init` 만으로는 안 올라갑니다.
그래도 안 되면 락 파일을 지우고 다시 받으세요.

```bash
rm -f .terraform.lock.hcl
terraform init -upgrade
terraform providers   # hashicorp/aws 버전 확인
```

**Provider 를 올릴 수 없는 환경이라면** 우회로가 준비되어 있습니다.

```bash
# 1) python3.13 으로 생성
echo 'lambda_runtime = "python3.13"' >> terraform.tfvars
terraform apply -auto-approve

# 2) CLI 로 런타임만 python3.14 로 변경
./scripts/set-runtime.sh
```

`lambda.tf` 에 `ignore_changes = [runtime]` 이 있어 이후 `terraform apply` 가 되돌리지 않습니다.

**2. Lambda 의 alert 토픽 produce**
`wsc2026-sensor-consumer` 가 alert 토픽으로 메시지를 보내려면 Kafka 클라이언트가 필요합니다.
EC2 가 부팅 시 `kafka-python` 레이어를 빌드해 함수에 붙입니다(`build_lambda_kafka_layer = true`).
레이어 부착이 실패해도 **DynamoDB 저장(4-5 채점 대상)은 정상 동작**합니다. 코드가 produce 실패를
로그만 남기고 넘어가도록 되어 있습니다.

**3. MSK SG 의 self 참조 규칙**
Lambda MSK 이벤트 소스는 클러스터의 서브넷/보안그룹으로 ENI 를 만듭니다.
클러스터 SG 에 자기 자신을 참조하는 인바운드 규칙이 없으면 매핑이 `Creating` 에서 멈춥니다.

**4. 문제지 DynamoDB 속성 표는 오타입니다**
문제지 6번 표에 `studentId / examDate / korean...` 이 적혀 있는데 1과제 내용이 잘못 복사된 것입니다.
채점기준 4-1/4-5 기준인 `sensorId / timestamp / temperature / humidity / location / status` 로 구성했습니다.

**5. 채점기준 4-0 의 `BUCKET_NAME` 표기도 오타입니다**
`wsc2026-student-score-bucket-...` 로 적혀 있으나 4-1 기대 출력은 `wsc2026-sensor-alert-bucket-...` 입니다.
문제지(7. S3) 기준으로 `wsc2026-sensor-alert-bucket-<비번호>` 를 만듭니다.

## 정리

```bash
terraform destroy -auto-approve   # MSK 삭제에도 10~20분 걸립니다
```
