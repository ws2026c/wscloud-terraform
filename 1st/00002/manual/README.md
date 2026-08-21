### 00002

- wskorea26-vpc-environment-sg를 가진 CloudShell VPC Environment 생성

- 

- S3 유의 사항
    - 로컬에서 미리 `web/main` 폴더를 생성하고 그 안에 파일들을 넣어 S3에 한번에 업로드 

- ECR 유의사항
    - KMS 관리형 키 또는 KMS CMK 사용

- EKS 설정 방법
    - 사전에 생성한 `wskorea26-vpc-environment-sg` 보안그룹의 443 인바운드를 허용하는 추가 보안 그룹 생성
    - KMS 암호화 방법 : 봉투 암호화 활성화
- EKS 노드 그룹 설정
    - App 노드그룹에는 반드시 테인트 설정 (테인트 키:값은 레이블과 동일)
    - 시작 템플릿 
        - 리소스 태그(Name) 설정
        - 메타데이터 응답 홉 제한 2 이상
    - Bottle Rocket이나 Amazon Linux 2023 사용
- EKS 앱 배포 : 앱 배포는 IRSA(IAM Role for Service Account) 생성 후 진행 Secret -> Deployment -> Service -> Ingress 순
- Lambda 함수의 권한은 kms:Decrypt 및 dynamodb:Query임. 또한 채점지에 명시되지 않은 TABLE_NAME에 DynamoDB의 테이블 명 주입
- Grafana 설치는 monitoring.sh의 쉘 명령으로 values.yaml과 함께 설치 (values.yaml에서 비번호 변경 필요) grafana-service와 grafana-ingress 적용하여 ALB 생성
-  Grafana의 경우 예상 지표는 container_cpu_usage_seconds_total, container_memory_working_set_bytes, kube_pod_container_status_running, kube_pod_container_status_restarts_total, container_network_receive_bytes_total
  - legend를 {{pod}} 로 바꾸고, Label Filter를 네임스페이스 명으로 바꾸는 것을 권장
