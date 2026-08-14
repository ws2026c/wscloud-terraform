# 00007 - Mod3

1. VPC 생성 및 SQS 생성

2. EKS 클러스터 생성
    - 클러스터 인증 모드 : EKS API
    - 추가 보안 그룹 : 필요 없음
    - 클러스터 엔드포인트 엑세스 : 퍼블릭 및 프라이빗
    - 추가 기능 : CoreDNS, Amazon VPC CNI, kube-proxy

3. EKS Addon Node Group 생성
    - App이 Addon NodeGroup에 배치되지 않도록 다음 테인트 사용 :
        - (키) CriticalAddonsOnly (값) true
        - (CoreDNS 같은 에드온도 배치할 수 있는 특정 테인트를 사용하는 것)
        - 노드 이름 지정을 위해 시작 템플릿 사용 및 응답 홉 제한 2 설정
        - Amazon Linux 2023 사용 권장
4. ECR 생성
    - 아래 Dockerfile 참조 or 배포된 Dockerfile 활용
    - app.py와 requirements.txt 모두 업로드 / 권한 부여 후 빌드
        ```Docker
        FROM python:3.13-alpine

        WORKDIR /app

        COPY requirements.txt .

        RUN pip install -r requirements.txt

        COPY app.py .

        CMD ["python", "app.py"]    
        ```
5. Karpenter 및 KEDA 설치
    - 네임스페이스 먼저 생성
    - KEDA 설치
        ```bash
        eksctl create iamserviceaccount \
        --cluster=${CLUSTER_NAME} \
        --namespace=keda \
        --name=keda-operator \
        --attach-policy-arn=arn:aws:iam::aws:policy/AmazonSQSReadOnlyAccess \
        --approve
        ```

        ```bash
        helm repo add keda https://kedacore.github.io/charts
        helm repo update

        helm upgrade --install keda keda/keda \
        --namespace keda \
        --create-namespace \
        --set serviceAccount.operator.create=false \
        --set serviceAccount.operator.name=keda-operator \
        --set serviceAccount.metricsServer.create=false \
        --set serviceAccount.webhooks.create=false \
        --set "tolerations[0].key=CriticalAddonsOnly" \
        --set "tolerations[0].operator=Exists" \
        --set "tolerations[0].effect=NoSchedule"
        ```
    - Karpenter 설치
    
        - 첨부된 `install_karpenter.sh` 실행
        - 앱에 적용될 보안 그룹 및 서브넷에 다음 태그 필요
            - (키) karpenter.sh/discovery (값) skm-eks-cluster
6. Deployment 및 Scaled Object, EC2 Node Class & NodePool 생성
