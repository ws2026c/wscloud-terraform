# 1과제 00002 배포 가이드
- S3, ECR 수동 업로드 필요
- EKS의 경우 엑세스 항목을 추가하여 자신의 root 계정의 ARN이나 IAM 계정으로 로그인 한 경우에는 IAM 유저의 ARN에 ClusterAdminPolicy를 부여
- ALB ReWrite 규칙은 수동 작성
- kubectl을 이용한 작업은 전부 수동
- 12. Monitoring 항목도 수동으로 구성