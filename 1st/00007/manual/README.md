### 00007

1. VPC 생성, 요구 사항 충족을 위해 vpc.md를 참고하여 엔드포인트 및 Flow Logs 활성화
2. KMS를 사전 생성하고 너무 제한적으로 작성하지 않아도 됨. Platform 키는 다중 리전 활성화
3. S3 생성 시 KMS 권한은 kms.md 참고
4. ECR 생성 시 푸시할 때 스캔 활성화
5. EKS 클러스터 생성
   - 추가 기능 : VPC CNI, CoreDNS, Kube-proxy, Pod Identity 에이전트 활성화
   - 클러스터 역할 생성 시 기본 부여되는 AmazonEKSClusterPolicy 외에도 kms.md를 참고하여 권한 부여 (kms 정책 자체에서 부여해도 상관 없음)
6. EKS 노드그룹
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
7. SA.md를 참고하여 Service Account 생성
8. k8s/ 폴더를 참고하여 secret -> deployment -> service 순으로 진행
9. ALB 생성 (보안 그룹은 아예 막지않고 403을 띄우기 위해 0.0.0.0/0 반드시 허용) -> 로드밸런서 컨트롤러 설치 후 나머지 yaml 적용
10. lambda_function.py를 참고하여 Lambda 생성, 코드와 환경변수 모두 암호화 (함수 권한과 KMS 권한은 kms.md 참고)
11. 
