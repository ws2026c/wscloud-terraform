# 00007 - Mod4 (Manual)

1. VPC (Public Subnet 2 / Private Subnet 2 (NAT G/W 포함) 구성)
2. EKS 생성
3. 노드 그룹 생성 (AMI는 Amazon Linux 2023으로 하며, KST 타임존 설정을 위해 다음 시작템플릿 사용)
   ```bash
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="==MYBOUNDARY=="
    
    --==MYBOUNDARY==
    Content-Type: text/x-shellscript; charset="us-ascii"
    
    #!/bin/bash
    timedatectl set-timezone Asia/Seoul
    
    --==MYBOUNDARY==--
   ```
3. Dockerfile 참고하여 자유롭게 ECR에 Push
4. `o11y`와 `monitoring` Namespace 생성
5. AWS Load Balancer Controller 설치
6. 각 파일 및 설치 스크립트를 참고하여 배포 (순서 : deployment -> service -> ingress -> loki 설치 -> otel 설치 -> grafana 설치)
   - Loki 설치는 `loki-values.yaml` 저장 후 아래 명령어로 설정
     ```bash
      helm repo add grafana https://grafana.github.io/helm-charts
      helm repo update
      helm install o11y-loki grafana/loki -n monitoring -f loki-values.yaml
     ```
