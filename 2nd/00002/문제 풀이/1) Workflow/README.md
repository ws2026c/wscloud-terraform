# 전국대회 2과제 00002 배포가이드

## 1) Workflow
### S3 버킷 생성
- wsc2026-student-score-bucket-<비번호>
- 버킷 -> 폴더 만들기 -> input

### DynamoDB
- 테이블 이름 : wsc2026-student-score
- 파티션 키 : studentId(문자열)
- 정렬 키 : examDate(문자열)
- 나머지 기본값 -> 생성

### IAM 역할 2개
#### IAM -> 역할 -> 역할 생성
- 역할 1 : wsc2026-lambda-student-role
    - 신뢰할 엔티티 : AWS 서비스 -> Lambda
    - 정책 붙이기
        - AmazonS3FullAccess
        - AmazonDynamoDBFullAccess
        - AWSSttepFunctionsFullAccess
        - CloudWatchLogsFullAccess
- 역할 2 : wsc2026-stepfunction-student-role
    - 신뢰할 엔티티 : AWS 서비스 -> StepFunctions
        - AmazonS3FullAccess
        - AWSLambdaRole

### Lambda - 성적 처리 함수
#### Lambda -> 함수 생성 -> 새로 작성
- 이름 : wsc2026-student-score-function
- 런타임 : Python 3.12
- 실행 역할 : 기존 역할 -> wsc2026-lambda-student-role

만든 뒤

- 코드 탭 : lambda_fuction.py(배포파일) 복붙
    - 파일 이름을 lambda_function.py에서 index.py로 변경
- 런타임 설정 편집 -> 핸들러 : index.handler
- 구성 -> 환경 변수 :
    - S3_BUCKET = wsc2026-student-score-bucket-<비번호>
    - DDB_TABLE = wsc2026-student-score
- 구성 -> 일반 구성 -> timeout 1분

## 배포파일 중간에 비워져 있는 TODO 채우기
- github에 있는 todo.js를 배포파일 도중의 비어있는 공간
    - def calculate_grade(average):...\
    ...pass\
    까지의 부분을 바꾸기


### Step Functions
#### Step Functions -> 상태 머신 생성 -> 코드로 작성
- 유형 -> 표준
- 이름 : wsc2026-student-score-workflow
- 역할 : 기존 역할 -> wsc2026-stepfunction-student-role
- 코드 -> github에 Step-Functions.js 참고
    - 버킷 비번호, Lambda ARN 수정 필요

### Lambda - 트리거 함수
#### Lambda -> 함수 생성
- 이름 : wsc2026-student-score-trigger
- 런타임 : Python 3.12
- 역할 : wsc2026-lambda-student-role

- 파일명 index.html / 핸들러 index.handler 로 변경.
    - github의 trigger.js 내용 복붙
- 환경 변수 : STATE_MACHINE_ARN -> 상태 머신 ARN

### S3 - 이벤트 알림
#### S3 -> 버킷 -> 속성 -> 이벤트 알림 -> 이벤트 알림 생성
- 이름 아무거나 (예 : csv-upload)
- 접두사 : input/
- 접미사 : .csv
- 이벤트 유형 : 모든 객체 생성 이벤트 체크
- 대상 -> Lambda 함수 -> wsc2026-student-score-trigger
저장

### 실행
#### 버킷 -> input 폴더 -> 업로드 -> 배포받은 test.csv

## 다시 실행 시키고 싶다면
- error/ 폴더 안 json파일 전부 삭제
- processed/ 폴더 안 test.csv 삭제
- input/ 에 test.csv 재 업로드
