### 00003

- KMS 키 정책 지정을 위해 role.md를 참고하여 필요한 리소스 먼저 생성
- **KMS 키는 kms.md를 참고하여 키 정책을 설정**
- mark-sg 보안그룹을 가진 CloudShell 반드시 생성
- VPC 생성

- DynamoDB는 Pod Role, Lambda Role 뿐만 아니라 테이블 자체 권한(리소스 기반 정책)에서도 권한 부여
  - wsc2026-book-pod-role에는 dynamodb:PutItem, wsc2026-book-function-role에는 dynamodb:Query
  - GSI 이름은 미지정이나, 구성한 Lambda 함수 기준인 `BookingIdIndex` 으로 설정.

- ECR 생성의 경우 태그 변경 불가능 설정 후 필터에 v1* 추가 (필터 추가 클릭 필수)

- EKS의 추가 보안 그룹은 mark-sg로부터 들어오는 443 인바운드 허용
  - 봉투 암호화 활성화
  - 추가 기능 : CoreDNS, VPC CNI, kube-proxy, EKS Pod Identity 에이전트
  - 인증 모드 : EKS API
  - 다음 명령으로 도메인 변경 후 저장
    ```bash
    kubectl edit -n kube-system cm coredns
    kubectl rollout restart deployment -n kube-system coredns
    ```

- EKS 노드 그룹 구성
  - 시작 템플릿 사용
    - 리소스 태그 Name 설정, 메타데이터 응답 홉 제한 2 이상
    - 다음 사용자 데이터 삽입
      ```toml
      [settings.kubernetes]
      cluster-domain = "wsc2026.skills.local"
      ```
  - 노드 개수는 2개 권장, Bottle Rocket 사용
  - Application Node Group은 테인트 설정 ([키] wsc2026/node [값] application)

- K8S
  - sa.txt를 참고하여 서비스 어카운트 생성
  - 네임스페이스 생성 후 k8s/ 폴더를 참고해 pdb -> configmap -> deployment -> service -> (로드밸런서 컨트롤러 설치 후) -> ingress 배포 (ALB 보안 그룹을 직접 만들어 security-groups: 에 직접 지정)
  - 클러스터 보안 그룹에서 ALB로 들어오는 모든 TCP 인바운드를 허용

- S3는 로컬에서 static/ 이라는 폴더를 만들어 파일을 전부 넣은 다음 S3에 업로드
- Lambda는 KMS로 코드와 환경 변수 둘다 암호화
    - 환경 변수 암호화 시 KMS 키 지정 및 전송 중 암호화 도우미를 활성화 하여 KMS 지정
    - 함수 URL 생성
    - 함수 코드는 lambda_function.py
- CloudFront
  - 생성 시 Pay as you go로 생성, WAF 비활성화, 원본 S3 지정
  - 생성 이후 Lambda, ALB 원본을 추가로 생성(Lambda의 경우 Lambda URL을 붙여넣으면 됨)하며 Lambda는 HTTPS, ALB는 HTTP
  - 기본값으로 생성된 S3의 원본 경로를 /static 으로 설정, ALB의 원본 경로는 없음
  - CloudFront 자체의 기본 루트 객체는 index.html
  - 동작에서 /v1/book* 경로는 Lambda로, /booking* 경로는 ALB로 설정. (S3는 기본값으로 이미 생성이 되어있으며, S3 외에는 전부 캐시 비활성화)
  - ALB의 보안 그룹에는 관리형 접두사로 CloudFront만 접근 가능하게 설정
  - WAF는 WAF 콘솔에서 별도로 생성하여 CloudFront와 직접 연결하며 관리형 규칙에서는 Core rule set, SQL 룰 적용 및 사용자 지정 규칙에서는 속도 기반 규칙으로 설정 후 문제지에 따라 설정 -> 조건 만족 시 403 반환

- monitoring/ 과 grafana/ 참고하여 Observability 구성
