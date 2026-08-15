# WSC2026 제2과제 - 2) Real-time data analytics (Terraform)

주문 로그 → Kinesis Data Stream → Managed Flink Studio 실시간 분석 환경.
Region: **ap-northeast-2**

## 채점기준 매핑

| 채점 | 확인 내용 | 담당 파일 |
|------|-----------|-----------|
| 2-1 | EC2 `t3.small`, Subnet `analytics-priv-a` | `ec2.tf`, `vpc.tf` |
| 2-2 | Listener `80 HTTP`, TG `wsc2026-analytics-tg 5000` | `alb.tf` |
| 2-3-A | `wsc2026-order-stream ACTIVE ON_DEMAND` | `kinesis.tf` |
| 2-3-B | `POST /order` → 5개 필드 채워진 JSON | `ec2.tf`(user_data), `iam.tf` |
| 2-4 | `wsc2026-analytics-flink READY ZEPPELIN-FLINK-3_0` | `flink.tf` |
| 2-5 | `GET /health` → `{"status":"healthy"}` | `alb.tf`, `templates/user_data.sh.tpl` |
| 2-6 | `systemctl is-active app` / `is-enabled app` → `active` / `enabled` | `templates/user_data.sh.tpl` |

## 파일 구성

| 파일 | 내용 |
|------|------|
| `provider.tf` | Provider, AL2023 AMI 조회 |
| `variables.tf` | 변수, 서브넷 정의 |
| `vpc.tf` | analytics-vpc, 4개 서브넷, IGW/NAT, 라우팅 테이블 3개 |
| `security.tf` | ALB SG(80 인터넷), EC2 SG(5000 ALB만) |
| `iam.tf` | EC2 Role(Kinesis Put + SSM), Flink Role(Kinesis 읽기 + Glue) |
| `kinesis.tf` | `wsc2026-order-stream` On-demand |
| `ec2.tf` | t3.small in `analytics-priv-a`, user_data 로 앱 배포 |
| `alb.tf` | ALB / TG / Listener |
| `flink.tf` | Glue DB + Studio Notebook (`ZEPPELIN-FLINK-3_0`, CloudFormation 경유) |
| `app/` | 배포파일 (`app.py`, `requirements.txt`) — user_data 가 `/opt/app/` 에 배치 |
| `templates/user_data.sh.tpl` | Python/venv/gunicorn + `app.service` 등록 |
| `docs/notebook.sql` | Studio Notebook 에서 실행할 Flink SQL |
| `scripts/check.sh` | 채점 2-1~2-6 자체 검증 |

## 배포

```bash
export AWS_DEFAULT_REGION=ap-northeast-2
cp terraform.tfvars.example terraform.tfvars

terraform init
terraform fmt -recursive
terraform validate
terraform apply -auto-approve
```

NAT + pip 설치 + gunicorn 기동까지 **약 3~5분** 걸립니다. Target 이 healthy 가 될 때까지 기다린 뒤 검증하세요.

```bash
chmod +x scripts/check.sh
./scripts/check.sh
```

## 수동 확인

```bash
export ALB_DNS=$(terraform output -raw alb_dns)
curl -s http://$ALB_DNS/health                       # {"status":"healthy"}
curl -s -X POST http://$ALB_DNS/order | jq .         # 주문 1건
curl -s -X POST http://$ALB_DNS/orders/generate | jq # 주문 10건
```

## 재적용 전 필수 — 실패한 스택 정리

CloudFormation 스택이 한 번 실패하면 `ROLLBACK_COMPLETE` 상태로 남고, 이 상태에서는 **업데이트가 불가능**해서 다음 `apply` 도 같은 자리에서 실패합니다. 반드시 먼저 지우세요.

```bash
aws cloudformation delete-stack --stack-name wsc2026-analytics-flink-studio --region ap-northeast-2
aws cloudformation wait stack-delete-complete --stack-name wsc2026-analytics-flink-studio --region ap-northeast-2

# Terraform state 에 남아 있으면 제거
terraform state list | grep cloudformation
terraform state rm aws_cloudformation_stack.flink_studio

terraform init      # time provider 추가되어 재초기화 필요
terraform apply -auto-approve
```

(`scripts/cleanup-failed-stack.sh` 로도 가능)

## Flink Studio Notebook 을 CloudFormation 으로 만드는 이유

Terraform AWS Provider 의 `aws_kinesisanalyticsv2_application` 리소스는 **Studio Notebook(ZEPPELIN 런타임)을 지원하지 않습니다.**

```
Error: Insufficient application_code_configuration blocks
Error: Unsupported block type - zeppelin_application_configuration
```

- `application_code_configuration` 이 필수(스트리밍 앱 전용)
- `zeppelin_application_configuration` 블록이 스키마에 없음

CloudFormation 의 `AWS::KinesisAnalyticsV2::Application` 은 `ZeppelinApplicationConfiguration` 과 `ApplicationMode: INTERACTIVE` 를 지원하므로,
`aws_cloudformation_stack` 안에 인라인 템플릿으로 생성합니다. 추가 Provider 설치가 필요 없고 `terraform destroy` 로 함께 삭제됩니다.

## 주의사항

**1. Flink Studio Notebook 은 채점 시 `READY` 여야 합니다.**
노트북을 RUN 하면 `RUNNING` 이 되어 2-4 가 오답 처리됩니다.
`docs/notebook.sql` 로 SQL 확인이 끝나면 반드시 **STOP** 하여 `READY` 로 되돌리세요.

```bash
aws kinesisanalyticsv2 stop-application --application-name wsc2026-analytics-flink \
  --application-configuration-update '{}' --region ap-northeast-2 2>/dev/null || \
aws kinesisanalyticsv2 stop-application --application-name wsc2026-analytics-flink --region ap-northeast-2
```

**2. 문제지 표기 확인 필요 2가지**

- IAM EC2 Role 이름이 문제지에 `wsc2026-alaytics-ec2-role` (analytics 오타)로 적혀 있어 **원문 그대로** 사용했습니다. 채점기준 2-x 에는 IAM 이름 확인 항목이 없습니다. 정정 공지가 있으면 `ec2_role_name` 변수만 바꾸면 됩니다.
- `analytics-pub-b` CIDR 이 문제지에 `10.21.0.0/24` 로 보이나, VPC CIDR 이 `10.20.0.0/16` 이므로 범위를 벗어납니다. `10.20.1.0/24` 로 구성했습니다. (`subnets` 변수에서 변경 가능)

**3. EC2 는 Private Subnet + NAT** 이므로 pip 설치와 SSM 등록 모두 NAT 경유입니다. NAT Gateway 를 지우면 2-6 이 실패합니다.

**4. 앱 배포 확인이 필요하면** SSM 으로 접속하세요.

```bash
EC2_ID=$(terraform output -raw ec2_instance_id)
aws ssm start-session --target $EC2_ID --region ap-northeast-2
# 또는
aws ssm send-command --instance-ids $EC2_ID --document-name AWS-RunShellScript \
  --parameters '{"commands":["tail -50 /var/log/user-data.log","systemctl status app --no-pager"]}' \
  --region ap-northeast-2
```

## 정리

```bash
terraform destroy -auto-approve
```
