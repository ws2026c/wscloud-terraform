# 00008 - Mod4

풀이 순서

1. VPC 생성 (Public 2개/Private 2개로 구성하며 NAT G/W 필요)
2. ECR 자유 생성 및 이미지 업로드 / 문제지 참고하여 SQS 생성
```Docker
FROM python:3.12-slim

WORKDIR /app

RUN pip install --no-cache-dir boto3

COPY worker.py .

CMD ["python", "worker.py"]
```

3. EKS 클러스터 생성
   - 클러스터 자체는 프라이빗 서브넷에 배치하지만, 외부 API 접근을 위해 엔드포인트 엑세스는 무조건 퍼블릭 및 프라이빗
   - 추가 기능 : kube-proxy, VPC CNI
4. 클러스터 생성 이후 작업
   - 4-1. Fargate 프로파일(문제지 참고) 생성
   - 4-2. CloudShell에서 클러스터에 연결하여 karpenter 네임스페이스 생성
   - 4-3. 클러스터 추가 기능에 다시 들어가 CoreDNS를 반드시 karpenter 네임스페이스에 생성
6. IRSA 생성 (순서대로)
```bash
eksctl create iamserviceaccount \
  --cluster=${CLUSTER_NAME} \
  --namespace=keda \
  --name=keda-operator \
  --role-name "${CLUSTER_NAME}-keda" \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonSQSFullAccess \
  --approve
```

```bash
export KARPENTER_NAMESPACE="karpenter"
export KARPENTER_VERSION=$(curl -sL "https://api.github.com/repos/aws/karpenter/releases/latest" | jq -r '.tag_name | ltrimstr("v")')
export K8S_VERSION=$(kubectl version -o json | jq -r '.serverVersion | "\(.major).\(.minor)"')
export AWS_PARTITION="aws"
export TEMPOUT="$(mktemp)"
curl -fsSL "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml" > "${TEMPOUT}"

aws cloudformation deploy \
  --stack-name "Karpenter-${CLUSTER_NAME}" \
  --template-file "${TEMPOUT}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterName=${CLUSTER_NAME}"

eksctl create iamserviceaccount \
  --cluster "${CLUSTER_NAME}" --region "${AWS_DEFAULT_REGION}" \
  --namespace "${KARPENTER_NAMESPACE}" --name karpenter \
  --role-name "${CLUSTER_NAME}-karpenter" \
  --attach-policy-arn "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerNodeLifecyclePolicy-${CLUSTER_NAME}" \
  --attach-policy-arn "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerIAMIntegrationPolicy-${CLUSTER_NAME}" \
  --attach-policy-arn "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerEKSIntegrationPolicy-${CLUSTER_NAME}" \
  --attach-policy-arn "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerInterruptionPolicy-${CLUSTER_NAME}" \
  --attach-policy-arn "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerResourceDiscoveryPolicy-${CLUSTER_NAME}" \
  --attach-policy-arn "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerZonalShiftPolicy-${CLUSTER_NAME}" \
  --role-only --approve

aws eks create-access-entry \
  --cluster-name "${CLUSTER_NAME}" \
  --principal-arn "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}" \
  --type EC2_LINUX --region "${AWS_DEFAULT_REGION}"
```

아래 파일을 iam_policy.json으로 저장

```json title="dd"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ],
      "Resource": "arn:aws:sqs:us-west-2:<계정ID>:skills-sqs-queue"
    }
  ]
}
```

```bash
aws iam create-policy \
  --policy-name skills-sqs-worker-policy \
  --policy-document file://iam_policy.json \
  --region us-west-2

eksctl create iamserviceaccount \
  --cluster=${CLUSTER_NAME} \
  --namespace=skills-sqs \
  --name=sqs-worker-sa \
  --role-name "${CLUSTER_NAME}-sqs-worker" \
  --attach-policy-arn=arn:aws:iam::$AWS_ACCOUNT_ID:policy/skills-sqs-worker-policy \
  --approve \
  --region=us-west-2
```

6. Helm 설치
```bash
helm repo add keda https://kedacore.github.io/charts
helm repo update

helm upgrade --install keda keda/keda \
  --namespace keda \
  --create-namespace \
  --set serviceAccount.operator.name=keda-operator \
  --set serviceAccount.operator.create=false \
  --set serviceAccount.operator.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CLUSTER_NAME}-keda"
```

```bash
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "${KARPENTER_VERSION}" \
  --namespace "${KARPENTER_NAMESPACE}" \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueue=${CLUSTER_NAME}" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/${CLUSTER_NAME}-karpenter" \
  --set controller.resources.requests.cpu=1 \
  --set controller.resources.requests.memory=1Gi \
  --set controller.resources.limits.cpu=1 \
  --set controller.resources.limits.memory=1Gi \
  --set "priorityClassName=system-cluster-critical" \
  --wait
```

7. 앱 자체 IAM Role 신뢰 관계에 다음 구문 삽입
```json
{
	"Effect": "Allow",
	"Principal": {
		"AWS": "arn:aws:iam::602620439352:role/skills-sqs-cluster-keda"
	},
	"Action": "sts:AssumeRole"
}
```

8. 파드의 보안 그룹(클러스터 보안그룹) 및 프라이빗 서브넷에 다음 태그 삽입
- 키 : karpenter.sh/discovery
- 값 : skills-sqs-cluster

9. 각 Yaml 적용
- 9-1. deployment.yaml 생성 및 적용
- 9-2. scaledobject.yaml (Trigger Authentication & Scaled Object) 생성 및 적용
- 9-3. node.yaml (NodeClass & NodePool) 생성 및 적용
