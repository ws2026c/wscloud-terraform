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
  - 추가 기능 : CoreDNS, VPC CNI, kube-proxy, EKS Pod Identity Agent
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
  - pdb -> configmap -> deployment -> service -> (로드밸런서 컨트롤러 설치 후) -> ingress 배포 (ALB 보안 그룹을 직접 만들어 security-groups: 에 직접 지정)
  - 클러스터 보안 그룹에서 ALB로 들어오는 모든 TCP 인바운드를 허용

- S3는 로컬에서 static/ 이라는 폴더를 만들어 파일을 전부 넣은 다음 S3에 업로드
- 
