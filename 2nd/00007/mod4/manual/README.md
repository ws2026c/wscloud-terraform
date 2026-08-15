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
4. `o11y`와 `monitoring` Namespace 생성
5. 각 Yaml 배포 (순서 : deployment ->
