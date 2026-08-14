export KARPENTER_NAMESPACE="kube-system"
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

helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "${KARPENTER_VERSION}" \
  --namespace "${KARPENTER_NAMESPACE}" \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueue=${CLUSTER_NAME}" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/${CLUSTER_NAME}-karpenter" \
  --set replicas=1 \
  --set controller.resources.requests.cpu=500m \
  --set controller.resources.requests.memory=512Mi \
  --set controller.resources.limits.cpu=500m \
  --set controller.resources.limits.memory=512Mi \
  --set "priorityClassName=system-cluster-critical" \
  --set "tolerations[0].key=CriticalAddonsOnly" \
  --set "tolerations[0].operator=Exists" \
  --set "tolerations[0].effect=NoSchedule"
  --wait
