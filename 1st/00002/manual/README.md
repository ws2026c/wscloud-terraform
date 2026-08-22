### 00002

- wskorea26-vpc-environment-sg를 가진 CloudShell VPC Environment 생성

- S3 유의 사항 : 로컬에서 미리 `web/main` 폴더를 생성하고 그 안에 파일들을 넣어 S3에 한번에 업로드 
- ECR 유의사항 : KMS 관리형 키 또는 KMS CMK 사용

- EKS 설정 방법
    - 사전에 생성한 `wskorea26-vpc-environment-sg` 보안그룹의 443 인바운드를 허용하는 추가 보안 그룹 생성
    - KMS 봉투 암호화 활성화
    - 추가 기능 : Amazon VPC CNI, CoreDNS, kube-proxy
- EKS 노드 그룹 설정
    - App 노드그룹에는 반드시 테인트 설정 (node-type: app)
    - 시작 템플릿 
        - 리소스 태그(Name) 설정
        - 메타데이터 응답 홉 제한 2 이상
    - Bottle Rocket이나 Amazon Linux 2023 사용
- EKS 앱 배포 : k8s/ 폴더에서 sa.txt 참고하여 Service Account 생성 후 Secret -> Deployment -> Service -> (로드밸런서 컨트롤러 설치) -> Ingress 순 배포 (Ingress 배포 시 ALB 부분은 설정할 필요가 없어짐)
- CloudFront
  - Pay as you go로 생성하며, WAF는 비활성화
  - S3 원본은 원본 경로를 /web/main 으로 설정하고, OAC 활성화, 사용자 헤더 삽입
  - ALB 원본은 원본 경로가 없으며, 사용자 헤더 삽입
  - **원본 이름이 정해져있기 때문에 일단 생성하고 삭제한 뒤, 재생성해야함.**
      - CloudFront를 처음 생성할 때는 S3로 원본 생성 -> ALB 원본 생성 -> 기본값 동작을 ALB 원본으로 설정 -> S3 원본 삭제 후 재생성 -> 기본값 동작을 S3로 설정하면 됨
  - CloudFront의 기본 루트 객체는 index.html로 설정
  - 동작은 총 2개로
      - 기본값 동작은 S3 원본과 연결 (캐싱 활성화)
      - ALB 동작은 경로 /book* 으로 지정, 캐싱 비활성화, 원본 요청 정책 : AllViewer
- Lambda 함수는 lambda_function.py 참고하여 생성하며, 권한은 kms:Decrypt 및 dynamodb:Query임. 또한 채점지에 명시되지 않은 TABLE_NAME에 DynamoDB의 테이블 명 주입
- Grafana 설치는 monitoring.sh의 쉘 명령으로 values.yaml과 함께 설치 (values.yaml에서 비번호 변경 필요) grafana-service와 grafana-ingress 적용하여 ALB 생성
-  Grafana의 경우 예상 지표는 container_cpu_usage_seconds_total, container_memory_working_set_bytes, kube_pod_container_status_running, kube_pod_container_status_restarts_total, container_network_receive_bytes_total
  - legend를 {{pod}} 로 바꾸고, Label Filter를 네임스페이스 명으로 바꾸는 것을 권장
