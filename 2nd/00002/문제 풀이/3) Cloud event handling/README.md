# 전국대회 2과제 00002 풀이
### 3) Cloud Event Handling (eu-west-1,아일랜드)

---

**1 VPC**

문제지 요구사항 대로 vpc 생성

---

**EC2 권한**

EC2-IAM

- 이름: `wsc2026-event-ec2-role`
- 정책: `AmazonSSMManagedInstanceCore`

보안 그룹 생성

- 이름: `wsc2026-event-sg`
- **인바운드 규칙: 0개**

---

**EC2**

요구 사항 맞춰서 제작

---


**SNS**

SNS → 주제 생성, 요구사항 대로 생성

---

**CloudTrail**

추적 생성

| 항목 | 값 |
|---|---|
| 이름 | `wsc2026-event-trail` |
| S3 버킷 | 새로 생성 (자동 이름) |
| 로그 SSE-KMS 암호화 | **체크 해제** |
| 이벤트 유형 |  관리 이벤트 |
| API 활동 |  **읽기 + 쓰기 둘 다** |

---

**Lambda 역할**
- 이름: `wsc2026-event-lambda-role`
- 정책: `AmazonEC2FullAccess`, `AmazonSNSFullAccess`, `CloudWatchLogsFullAccess`
- **인라인 정책 추가**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::<계정ID>:role/wsc2026-event-ec2-role"
    }
  ]
}
```

---

**Lambda 함수**

**Lambda → 함수 생성** -> github에 있는 .py 파일들을 이름에 맞게 복사해서 넣으면 됨 -> 해당 python 파일들은 배포파일의 TODO 내용을 추가한 것

공통:

- 런타임 **Python 3.12** / 역할 `wsc2026-event-lambda-role`
- 파일명 `lambda_function.py` → **`index.py`로 변경**
- 핸들러: **`index.handler`**

**함수별 설정표**

| 함수 이름 | 파일 | 환경 변수 | 제한 시간 |
|---|---|---|---|
| `wsc2026-sg-remediation` | `wsc2026-sg-remediation.py` | `SNS_TOPIC_ARN` / `SECURITY_GROUP_ID` | 1분 |
| `wsc2026-role-remediation` | `wsc2026-role-remediation.py` | `SNS_TOPIC_ARN` / `INSTANCE_ID` / `ROLE_NAME`=`wsc2026-event-ec2-role` | 1분 |
| `wsc2026-ec2-terminate-alert` | `wsc2026-ec2-terminate-alert.py` | `SNS_TOPIC_ARN` | 1분 |
| `wsc2026-ec2-type-remediation` | `wsc2026-ec2-type-remediation.py` | `SNS_TOPIC_ARN` / `INSTANCE_ID` / `INSTANCE_TYPE`=`t3.micro` | **5분** |
| `wsc2026-ec2-stop-remediation` | `wsc2026-ec2-stop-remediation.py` | `SNS_TOPIC_ARN` / `INSTANCE_ID` | **5분** |
| `wsc2026-tag-alert` | `wsc2026-tag-alert.py` | `SNS_TOPIC_ARN` / `INSTANCE_ID` / `REQUIRED_TAG_KEY`=`Name` / `REQUIRED_TAG_VALUE`=`wsc2026-event-ec2` | 1분 |

---

**EventBridge 규칙**

EventBridge → 규칙 생성 → 이벤트 패턴 "사용자 지정 패턴(JSON)" → 대상: Lambda 함수
- 역할 선택은 기본 값

- `wsc2026-sg-change-rule` -> `wsc2026-sg-remediation`

```json
{
  "source": ["aws.ec2"],
  "detail-type": ["AWS API Call via CloudTrail"],
  "detail": {
    "eventSource": ["ec2.amazonaws.com"],
    "eventName": ["AuthorizeSecurityGroupIngress"]
  }
}
```

- `wsc2026-role-change-rule` -> `wsc2026-role-remediation`

```json
{
  "source": ["aws.ec2"],
  "detail-type": ["AWS API Call via CloudTrail"],
  "detail": {
    "eventSource": ["ec2.amazonaws.com"],
    "eventName": ["AssociateIamInstanceProfile", "ReplaceIamInstanceProfileAssociation"]
  }
}
```

- `wsc2026-ec2-terminate-rule` -> `wsc2026-ec2-terminate-alert`

```json
{
  "source": ["aws.ec2"],
  "detail-type": ["EC2 Instance State-change Notification"],
  "detail": {
    "state": ["terminated", "shutting-down"]
  }
}
```

- `wsc2026-ec2-type-change-rule` -> `wsc2026-ec2-type-remediation`

```json
{
  "source": ["aws.ec2"],
  "detail-type": ["AWS API Call via CloudTrail"],
  "detail": {
    "eventSource": ["ec2.amazonaws.com"],
    "eventName": ["ModifyInstanceAttribute"]
  }
}
```

- `wsc2026-ec2-stop-rule` ->`wsc2026-ec2-stop-remediation`

```json
{
  "source": ["aws.ec2"],
  "detail-type": ["EC2 Instance State-change Notification"],
  "detail": {
    "state": ["stopping", "stopped"]
  }
}
```

- `wsc2026-tag-change-rule` -> `wsc2026-tag-alert`

```json
{
  "source": ["aws.tag"],
  "detail-type": ["Tag Change on Resource"],
  "detail": {
    "service": ["ec2"],
    "resource-type": ["instance"]
  }
}
```

- 이 곳에서 'wsc2026-ec2-stop','wsc2026-tag' 이 두 종류는 문제지에는 없지만, 채점에서는 반드시 요구되는 리소스들

---

**AWS Config**

- 레코더 설정
1. **시작하기**
2. 기록 전략: "**특정 리소스 유형**" → `AWS EC2 Instance`, `AWS EC2 SecurityGroup` 추가
3. 기록 빈도: 연속(기본) / IAM 역할: 서비스 연결 역할 생성(기본) / S3: 버킷 생성(기본) / SNS: 비활성(기본)
4. 다음 → (규칙 추가 화면은 건너뛰기) → 확인

- 규칙 1 

  1. **규칙 → 규칙 추가** → "AWS 관리형 규칙 추가"
  2. 검색: `ssh` → `restricted-ssh` 선택
  3. 이름을 `wsc2026-sg-ssh-rule` 로 변경
  4. 파라미터 없음 → 규칙 추가

- 규칙 2

1. **규칙 추가** → 검색: **`required-tags`** 선택
2. **이름을 `wsc2026-required-tags-rule` 로 변경**
3. **범위(Scope): "리소스" 선택 → EC2: Instance 만 추가**
4. 파라미터: `tag1Key` = `Name` / `tag1Value` = 비움
5. 규칙 추가

