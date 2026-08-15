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
4. 대상그룹 이름이 필요하므로 Target Group Binding 방식 필요
   - o11y-app-tg는 8080, o11y-grafana-tg는 3000
   - 대상 그룹 유형은 모두 IP
   - o11y-app-tg의 상태 검사 경로는 /healthz이며 o11y-grafana-tg는 /api/health 경로
   - ALB에서 들어오는 3000, 8080 포트를 보안그룹에서 열어줄 필요가 있음
   - tgb.yaml과 grafana.yaml의 대상그룹 ARN을 적용시켜야함.
5. `o11y`와 `monitoring` Namespace 생성
6. AWS Load Balancer Controller 설치
7. 각 파일 및 설치 스크립트를 참고하여 배포 (순서 : deployment -> service -> tgb -> loki 설치 -> otel 설치 -> grafana 설치)
   - Data Sources에서 Loki 선택 후 URL을 http://o11y-loki.monitoring.svc.cluster.local:3100 로 설정
8. 반드시 대시보드 이름 및 패널 이름, 배치 및 범례를 문제지와 같게 설정
예시 쿼리
```bash
sum by (level) (
  count_over_time(
    {k8s_namespace_name="o11y"}
    | json
    | __error__ = "" [$__interval]
  )
)
```

```bash
sum by (level) (
  count_over_time(
    {k8s_namespace_name="o11y"}
    | json
    | __error__ = "" [$__range]
  )
)
```
