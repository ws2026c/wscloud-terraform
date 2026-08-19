### 00003

- KMS 키 정책 지정을 위해 kms.md를 참고하여 관련 리소스를 먼저 생성하는 것을 권장
- mark-sg 보안그룹을 가진 CloudShell 반드시 생성
- VPC 생성

- DynamoDB는 Pod Role, Lambda Role 뿐만 아니라 테이블 자체 권한(리소스 기반 정책)에서도 권한 부여
  - wsc2026-book-pod-role에는 dynamodb:PutItem, wsc2026-book-function-role에는 dynamodb:Query
  - GSI 이름은 미지정이나, 구성한 Lambda 함수 기준인 `BookingIdIndex` 으로 설정.

- ECR 생성의 경우 태그 변경 불가능 설정 후 필터에 v1* 추가 (필터 추가 클릭 필수)

- EKS의 추가 보안 그룹은 mark-sg로부터 들어오는 443 인바운드 허용
  - 봉투암호화에 사용할 KMS 키 정책도 역시 kms.md 참고
  - 추가 기능 : CoreDNS, VPC CNI, kube-proxy, EKS Pod Identity Agent
  - 인증 모드 : EKS API
  - 다음 명령으로 도메인 변경 후 저장
    ```bash
    kubectl edit -n kube-system cm coredns
    kubectl rollout restart deployment -n kube-system coredns
    ```

- EKS 노드 그룹 구성
