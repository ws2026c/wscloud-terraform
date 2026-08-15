# WSC2026 Student Score Serverless Pipeline (Terraform)

S3 → Lambda(트리거) → Step Functions → Lambda(성적 처리) → DynamoDB 파이프라인 IaC.
Region: `ap-southeast-1`

## 최종 확인 (채점 명령 그대로)

```bash
export AWS_DEFAULT_REGION=ap-southeast-1
BUCKET_NAME=wsc2026-student-score-bucket-111

# 1-1
aws s3 ls s3://$BUCKET_NAME/
# 1-5-A
aws dynamodb get-item --table-name wsc2026-student-score \
  --key '{"studentId":{"S":"STU1020"},"examDate":{"S":"2026-05-30"}}' \
  --query "Item.[studentId.S,average.N,grade.S]" --output text
aws s3 ls s3://$BUCKET_NAME/processed/
# 1-5-B
aws s3 ls s3://$BUCKET_NAME/error/
```

> `--max-items` 는 `--output text` 와 같이 쓰면 페이지네이션 토큰 `None` 이 한 줄 더 출력되어
> `$(...)` 로 받을 때 `Unknown options: None` 오류가 납니다. 스크립트는 `--max-results` 로 교체했습니다.

## v4 — 실행이 안 될 때

```bash
./scripts/run-now.sh 111      # 비번호
```

업로드 → S3 이벤트 → 워크플로우를 강제로 진행하면서 끊긴 지점을 출력합니다.
S3 이벤트가 오지 않으면 워크플로우를 직접 실행해 나머지 구간을 검증하고,
실패 시 실패한 State 이름과 원인, Lambda 로그까지 출력합니다.

> **test.csv 는 반드시 원본(497 bytes)** 이어야 합니다. 원본은 CRLF 개행에 끝 개행이 없어
> 정확히 497 bytes 이고, 채점 1-5-A 가 `497 test.csv` 를 확인합니다.
> 에디터에서 다시 저장하면 크기가 달라져 오답이 됩니다.
> `run-now.sh` 는 크기가 497 이 아니면 내장된 원본으로 자동 교체합니다.

## ⚠️ v3 수정 — `reset-and-run.sh` 가 업로드 전에 죽던 버그

`set -euo pipefail` 상태에서 아래 줄이 문제였습니다.

```bash
aws s3 ls s3://$BUCKET/input/ | awk '{print $4}' | grep -v '^$' | while read -r f; do ... done
```

`input/` 에 폴더 마커(0-byte)만 있으면 `grep` 이 아무것도 못 찾아 **exit 1** 을 내고,
`pipefail` + `set -e` 때문에 **test.csv 업로드 직전에 스크립트가 종료**됩니다.
그래서 워크플로우가 한 번도 실행되지 않아 이런 증상이 나옵니다.

| 증상 | 원인 |
|------|------|
| 1-1 이 `PRE input/` 만 출력 | 워크플로우 미실행 → `processed/` `error/` 가 비어서 prefix 자체가 없음 |
| 1-5-A 가 `None` | DynamoDB 에 저장된 항목이 없음 |
| 1-5-B 가 에러 | `error/` 에 객체가 없어 `aws s3 ls` 가 exit 1 |

→ `set -e` 제거 + `list-objects-v2` 기반으로 재작성했고, 실행이 시작되지 않으면 즉시 알려줍니다.
→ 단계별 원인 추적용 `scripts/diagnose.sh` 를 추가했습니다.

## 채점기준 대조 수정사항 (v2)

| 채점항목 | 실패 원인 | 수정 |
|----------|-----------|------|
| 1-3 | Lambda 함수명이 `wsc2026-student-score-process` 였음. 채점은 `wsc2026-student-score-function` 으로 조회 | 함수명을 `wsc2026-student-score-function` 으로 변경 |
| 1-5-A | `processed/` 0-byte 폴더 마커 때문에 `aws s3 ls` 출력에 빈 줄이 추가됨 (`test.csv` 한 줄만 나와야 함) | `processed/` 마커 생성 제거 |
| 1-5-B | `error/` 0-byte 폴더 마커 때문에 error json 4개 외 빈 줄이 추가됨 | `error/` 마커 생성 제거 |
| 1-1 / 1-3 / 1-5 | 버킷명 비번호 불일치 시 `head-bucket` 부터 실패 → 버킷 기반 항목이 전부 오답 | `student_number` 기본값 제거(필수 입력) + validation |

폴더 마커는 **`input/` 에만** 생성합니다.

- `input/` : 워크플로우가 원본 csv를 `processed/` 로 옮기면 prefix가 사라지므로, 1-1의 `PRE input/` 유지를 위해 마커 필요
- `processed/` `error/` : 워크플로우 실행 결과물(test.csv, error json)이 들어가면서 자동으로 prefix가 생기므로 마커 불필요. 마커가 있으면 1-5 가 오답 처리됨

## 파일 구성

| 파일 | 내용 |
|------|------|
| `provider.tf` | Terraform / AWS Provider, 리전 설정 |
| `variables.tf` | 변수 및 locals (버킷명 = `wsc2026-student-score-bucket-<비번호>`) |
| `s3.tf` | S3 버킷, `input/` `processed/` `error/` prefix, S3 Event Notification |
| `dynamodb.tf` | `wsc2026-student-score` 테이블 (PK `studentId` / SK `examDate`) |
| `iam.tf` | `wsc2026-lambda-student-role`, `wsc2026-stepfunction-student-role` (최소권한) |
| `lambda.tf` | 성적 처리 Lambda + 트리거 Lambda (Python 3.12, `index.handler`) |
| `stepfunctions.tf` | `wsc2026-student-score-workflow` (STANDARD) |
| `workflow.asl.json` | State Machine 정의(ASL 템플릿) |
| `outputs.tf` | 생성 리소스 출력 |
| `src/process/index.py` | 성적 처리 함수 (제공 코드의 TODO 완성본) |
| `src/trigger/index.py` | S3 업로드 감지 → `start_execution` |
| `scripts/check.sh` | 채점기준 1-1~1-5-B 자체 검증 |
| `scripts/reset-and-run.sh` | 채점 직전 상태 초기화 + test.csv 업로드 |
| `scripts/run-now.sh` | **원샷 실행+진단.** 업로드→트리거→워크플로우를 강제 진행하며 끊긴 지점 출력 |
| `scripts/diagnose.sh` | S3 알림 → 트리거 → 워크플로우 단계별 원인 추적 |

## 배포 명령어

```bash
# 0) 자격 증명 (예시)
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=ap-southeast-1

# 1) 변수 파일 준비 (비번호 수정)
cp terraform.tfvars.example terraform.tfvars

# 2) 초기화 / 검증 / 배포
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply -auto-approve

# 3) 출력 확인
terraform output
```

## 동작 테스트

```bash
BUCKET=$(terraform output -raw s3_bucket_name)

# 테스트 CSV 업로드 (자동으로 트리거 Lambda → Step Functions 실행)
aws s3 cp test.csv s3://$BUCKET/input/test.csv --region ap-southeast-1

# Step Functions 실행 결과 확인
aws stepfunctions list-executions \
  --state-machine-arn $(terraform output -raw state_machine_arn) \
  --region ap-southeast-1

# 결과 확인
aws s3 ls s3://$BUCKET/processed/ --region ap-southeast-1   # test.csv 이동 확인
aws s3 ls s3://$BUCKET/error/     --region ap-southeast-1   # 오류 JSON 4건
aws dynamodb scan --table-name wsc2026-student-score \
  --region ap-southeast-1 --query 'Count'                   # 5
```

제공된 `test.csv` 기준 기대 결과: `{"statusCode": 200, "processed": 5, "errors": 4}`

| studentId | 결과 | 사유 / 등급 |
|-----------|------|-------------|
| STU1020 | OK | avg 96.6 → A |
| STU2002 | ERROR | INVALID_FORMAT (english = "eighty") |
| STU1220 | OK | avg 76.6 → C |
| STU2004 | ERROR | MISSING_FIELD (name 없음) |
| STU1203 | OK | avg 87.2 → B |
| STU2001 | ERROR | MISSING_FIELD (history 없음) |
| STU0511 | OK | avg 92.0 → A |
| STU4444 | OK | avg 58.0 → F |
| (없음) | ERROR | MISSING_FIELD (studentId 없음) |

## 자체 채점 (권장)

```bash
chmod +x scripts/*.sh

# 채점 직전 상태 만들기: processed//error//DynamoDB 비우고 test.csv 업로드 -> 자동 실행
./scripts/reset-and-run.sh 103

# 채점기준 1-1 ~ 1-5-B 를 그대로 실행해 PASS/FAIL 출력
./scripts/check.sh 103

# 위에서 실행이 안 되면 단계별 원인 추적
./scripts/diagnose.sh 103
```

전부 PASS 가 나와야 합니다. (103 자리에 본인 비번호)

`reset-and-run.sh` 없이 손으로 확인하려면:

```bash
BUCKET=wsc2026-student-score-bucket-103
aws s3 cp test.csv s3://$BUCKET/input/test.csv --region ap-southeast-1
sleep 15
aws s3 ls s3://$BUCKET/            # PRE error/ input/ processed/
aws s3 ls s3://$BUCKET/processed/  # 497 test.csv
aws s3 ls s3://$BUCKET/error/      # error json 4개
```

## 채점 전 초기화

```bash
BUCKET=$(terraform output -raw s3_bucket_name)
aws s3 rm s3://$BUCKET/processed/ --recursive --region ap-southeast-1
aws s3 rm s3://$BUCKET/error/     --recursive --region ap-southeast-1
aws s3 rm s3://$BUCKET/input/     --recursive --region ap-southeast-1

# DynamoDB 전체 삭제
aws dynamodb scan --table-name wsc2026-student-score --region ap-southeast-1 \
  --projection-expression "studentId,examDate" --query "Items[]" --output json \
| jq -c '.[]' | while read -r k; do
    aws dynamodb delete-item --table-name wsc2026-student-score \
      --region ap-southeast-1 --key "$k"
  done
```

> `input/` 마커는 지우지 마세요. 지우면 1-1 의 `PRE input/` 이 사라집니다.
> (`scripts/reset-and-run.sh` 는 마커를 자동으로 복구합니다.)

## 정리

```bash
terraform destroy -auto-approve
```

## Workflow 흐름

```
[Start] → CheckS3File (s3:headObject)
            ├─ 실패 → FileNotFound (Fail)
            ↓
        ProcessStudentData (lambda:invoke, Exponential Backoff 재시도 2s/×2/3회)
            ↓
        CheckResult (Choice)
            ├─ statusCode == 200 → MoveToProcessed(copyObject) → DeleteInputAfterProcessed(deleteObject) → [End]
            └─ Otherwise         → MoveToError(copyObject)     → DeleteInputAfterError(deleteObject)     → WorkflowFailed (Fail)
```

> AWS SDK 통합은 1 Task = 1 API 호출이므로, `CopyObject + DeleteObject`를 각각 Task로 분리했습니다.
