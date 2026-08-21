### 00007

1. VPC 생성, 요구 사항 충족을 위해 vpc.md를 참고하여 엔드포인트 및 Flow Logs 활성화
2. KMS를 사전 생성하고 너무 제한적으로 작성하지 않아도 됨. Platform 키는 다중 리전 활성화
3. S3 생성 시 KMS 권한은 kms.md 참고하여 생성 및 객체 업로드
4. ECR 생성 시 푸시할 때 스캔 활성화
5. EKS 클러스터 생성
   - 봉투 암호화 활성화 (쿠버네티스 내부가 자동으로 암호화 됨)
   - 추가 기능 : VPC CNI, CoreDNS, Kube-proxy, Pod Identity 에이전트 활성화
   - 인증 모드 : AWS API
   - 클러스터 역할 생성 시 기본 부여되는 AmazonEKSClusterPolicy 외에도 kms.md를 참고하여 권한 부여 (kms 정책 자체에서 부여해도 상관 없음)
   - 추가 보안그룹 인바운드는 CloudShell로 설정 (443)
7. EKS 노드그룹
   - 노드 그룹 역할 생성 시 기본 부여되는 4가지 정책 외에도 kms:Decrypt 부여
   - AMI는 반드시 Amazon Linux 2023으로 하며 t3.medium 사용 권장, 노드 그룹 및 시작 템플릿에 Name 태그 부여 및 메타데이터 응답 홉 제한은 2 이상 설정
   - 사용자 데이터 (개행이나 공백이 추가로 들어가지 않도록 유의)
    ```bash
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="==MYBOUNDARY=="
    
    --==MYBOUNDARY==
    Content-Type: text/x-shellscript; charset="us-ascii"
    
    #!/bin/bash
    timedatectl set-timezone Asia/Seoul
    
   --==MYBOUNDARY==--
   ```
8. SA.md를 참고하여 Service Account 생성
9. k8s/ 폴더를 참고하여 secret -> deployment -> service 순으로 진행
10. ALB 생성 (보안 그룹은 아예 막지않고 403을 띄우기 위해 0.0.0.0/0 반드시 허용) -> 로드밸런서 컨트롤러 설치 후 나머지 yaml 적용 -> Cluster 보안 그룹에 ALB로부터 들어오는 8080 허용)
   - Lambda 전용 보안그룹은 임의로 생성
   - 조건 별로 분기 (경로가 /v1/book이며 메서드가 POST인 경우 unicorn-tg로, 경로가 /v1/book이며 메서드가 GET이라면 Lambda 전송, 경로가 /health라면 반드시 unicorn-tg로 전송, 기본값은 403)
11. lambda_function.py를 참고하여 Lambda 생성, 코드와 환경변수 모두 암호화 (함수 권한과 KMS 권한은 kms.md 참고)
12. CloudFront 생성 시 WAF 옵션 비활성화 / 생성 시 원본 S3 지정
    - S3에 자동으로 권한 (OAC 정책) 이 생성되는데, 그 정책에서 ArnLike를 StringEquals로 변경
    - ALB 원본을 직접 연결하지않고 CloudFront의 VPC Origin을 생성하여 생성 (원본 포트는 80)
    - 최종적으로 원본은 S3와 VPC Origin이 되어야하며, S3 동작은 기본값, VPC Origin(ALB) 동작은 /v1/book* 이여야 함 (S3만 캐싱 활성화)
    - WAF는 us-east-1 리전에서 생성하며 CloudFront와 별도로 연결, Core rule과 KnownBadInputs 을 연결하고 속도 기반 정책으로 unicorn-rate-limit 생성
      - 차단 시 응답은 Request blocked by Unicorn WAF임. (HTTP 403은 응답 본문이 아님에 주의!)
13. Security의 역할 구성의 경우 신뢰 관계를 AWS 계정 설정 후 외부 ID 필요 선택 후 지정된 외부 ID 입력 이후 권한 입력
    - 정책을 먼저 만들지 말고 인라인 정책으로 생성 (security-policy.json 참고)
14. observability/ 폴더를 참고하여 Fluent-bit와 monitoring 구성 (Fluent-bit의 경우 irsa.txt로 서비스 어카운트를 생성)
