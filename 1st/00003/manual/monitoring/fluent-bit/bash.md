1
```bash
aws iam create-policy \
    --policy-name FluentBitIAMPolicy \
    --policy-document file://fluent_policy.json

eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=observability \
  --name=fluent-bit-sa \
  --override-existing-serviceaccounts \
  --role-name FluentBitIAMRole \
  --attach-policy-arn=arn:aws:iam::$AWS_ACCOUNT_ID:policy/FluentBitIAMPolicy \
  --approve
```

2
트래픽 발생 후\
cloudwatch -> logs -> /wsc2026/eks/application -> 안뜬다면

```bash
kubectl -n observability get pod -l k8s-app=fluent-bit -o wide
kubectl -n wsc2026 get pod -o wide
```
-> 위 명령어가 정상적으로 출력 (running)

```bash
kubectl -n observability patch ds fluent-bit --type json \
  -p '[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]'

kubectl -n observability patch ds fluent-bit \
  -p '{"spec":{"template":{"spec":{"tolerations":[{"operator":"Exists"}]}}}}'

kubectl -n observability get pod -l k8s-app=fluent-bit -o wide

```