# WSC2026 제2과제 - 3) Cloud Event Handling (Terraform)

보안/비용 위협 발생 시 자동 복구 + 알림. Region: **eu-west-1**

## ⚠️ 채점기준과 문제지의 리소스 이름이 다릅니다

| 구분 | 채점기준 3-x | 문제지 / lambda.md |
|------|--------------|---------------------|
| Lambda | `wsc2026-ec2-stop-remediation`<br>`wsc2026-ec2-terminate-alert`<br>`wsc2026-sg-remediation`<br>`wsc2026-tag-alert` | `wsc2026-sg-remediation`<br>`wsc2026-role-remediation`<br>`wsc2026-ec2-terminate-alert`<br>`wsc2026-ec2-type-remediation` |
| Rule | `wsc2026-ec2-stop-rule`<br>`wsc2026-ec2-terminate-rule` | `wsc2026-sg-change-rule`<br>`wsc2026-role-change-rule`<br>`wsc2026-ec2-terminate-rule`<br>`wsc2026-ec2-type-change-rule` |
| AWS Config | `wsc2026-sg-ssh-rule`<br>`wsc2026-required-tags-rule` | 언급 없음 |

**양쪽을 모두 만족하는 상위집합으로 구성했습니다.** Lambda 6개, EventBridge Rule 6개, Config Rule 2개.
채점은 지정한 이름의 리소스가 존재하는지만 확인하므로 추가 리소스는 감점 요인이 아닙니다.

## 채점기준 매핑

| 채점 | 확인 내용 | 담당 |
|------|-----------|------|
| 3-0 | EC2 중지 + SG 에 SSH 인바운드 추가 (위반 유발) | — |
| 3-1 | SNS `wsc2026-event-alert` + Lambda 4종 python3.12 | `sns.tf`, `lambda.tf` |
| 3-2 | `wsc2026-ec2-stop-rule` → stop-remediation<br>`wsc2026-ec2-terminate-rule` → terminate-alert | `eventbridge.tf` |
| 3-3 | Config 규칙 2종 ACTIVE | `config.tf` |
| 3-4 | EC2 `running` 복구 / SG Inbound `0` 복구 | `lambda.tf`, `src/index.py` |
| 3-5 | required-tags NON_COMPLIANT 없음 | `config.tf`, `ec2.tf` |

## 파일 구성

| 파일 | 내용 |
|------|------|
| `vpc.tf` | event-vpc 172.16.0.0/16, event-pub-a/b, event-igw, event-pub-rtb |
| `ec2.tf` | `wsc2026-event-ec2` t3.micro, `wsc2026-event-sg`(인바운드 0개), EC2 Role |
| `sns.tf` | `wsc2026-event-alert` |
| `cloudtrail.tf` | `wsc2026-event-trail` Management Read/Write + S3 |
| `lambda.tf` | Lambda 6종 (`index.handler`, python3.12) + 최소권한 Role |
| `eventbridge.tf` | Rule 6종 + Target + Lambda Permission |
| `config.tf` | Configuration Recorder + Config 규칙 2종 |
| `src/index.py` | 배포파일 TODO 완성본 (FUNCTION_ROLE 로 6개 동작 분기) |
| `scripts/check.sh` | 채점 3-0~3-5 자체 검증 (위반 유발 포함) |

## 배포

```bash
export AWS_DEFAULT_REGION=eu-west-1
cp terraform.tfvars.example terraform.tfvars   # student_number 수정

terraform init
terraform validate
terraform apply -auto-approve
```

## 검증

```bash
chmod +x scripts/check.sh
./scripts/check.sh
```

`check.sh` 는 채점 3-0 과 똑같이 **EC2 를 중지하고 SG 에 SSH 규칙을 추가**한 뒤,
자동 복구로 `running` / `inbound 0` 으로 돌아오는지 최대 5분간 지켜봅니다.

## 동작 방식

```
[SG 인바운드 추가]  --CloudTrail--> wsc2026-sg-change-rule      --> wsc2026-sg-remediation      규칙 삭제 + SNS
[EC2 중지]          --StateChange-> wsc2026-ec2-stop-rule       --> wsc2026-ec2-stop-remediation 재시작 + SNS
[EC2 종료]          --StateChange-> wsc2026-ec2-terminate-rule  --> wsc2026-ec2-terminate-alert  SNS 만
[IAM Role 변경]     --CloudTrail--> wsc2026-role-change-rule    --> wsc2026-role-remediation     Profile 원복 + SNS
[인스턴스 타입 변경] --CloudTrail--> wsc2026-ec2-type-change-rule--> wsc2026-ec2-type-remediation 타입 원복 + SNS
[태그 변경]         --aws.tag-----> wsc2026-tag-change-rule     --> wsc2026-tag-alert            태그 복구 + SNS
```

SNS 메시지는 lambda.md 규격 그대로입니다.

```json
{"event":"SG_INBOUND_ADDED","timestamp":"2026-05-26T15:30:00Z","detail":"...","action":"RESTORED"}
```

## 주의사항

**1. AWS Config Recorder 는 리전당 1개만 존재할 수 있습니다.**
eu-west-1 에 이미 Recorder 가 있으면 `MaxNumberOfConfigurationRecordersExceededException` 이 납니다.
그 경우 `config.tf` 의 recorder/delivery_channel/status 3개 리소스를 주석 처리하고 Config 규칙만 남기세요.
(기존 Recorder 를 그대로 사용하게 됩니다.)

**2. Config 최초 평가에 몇 분 걸립니다.** 3-3 / 3-5 가 바로 안 나오면 5분 후 재확인하세요.

**3. CloudTrail 기반 감지는 지연이 있습니다.**
`AuthorizeSecurityGroupIngress` 같은 API 이벤트는 EventBridge 도달까지 보통 1~3분 걸립니다.
채점 3-4 의 `sleep 30` 은 3-1~3-3 을 거친 뒤 실행되므로 실제로는 여유가 있습니다.
반면 EC2 중지/종료는 State-change 이벤트라 수 초 내 전달됩니다.

**4. Terraform 이 자동 복구 결과를 되돌리지 않도록** EC2 의 `instance_type` / `iam_instance_profile`,
SG 의 `ingress` 는 `lifecycle.ignore_changes` 로 제외했습니다.

**5. 자기 호출 루프 방지** — 타입 원복 Lambda 는 현재 타입이 이미 정상이면 API 를 호출하지 않고,
태그 복구 Lambda 는 태그가 이미 정상이면 `ALERT_ONLY` 로 끝냅니다.

## 정리

```bash
terraform destroy -auto-approve
```
