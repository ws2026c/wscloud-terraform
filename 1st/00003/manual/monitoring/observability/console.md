yaml 파일 배포 순서\
rbac.yaml -> node_exporter.yaml -> alert_manage.yaml -> kube-states-metrics.yaml -> prometheus.yaml -> grafana.yaml

```bash
cat > grafana-trust.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "pods.eks.amazonaws.com" },
      "Action": ["sts:AssumeRole", "sts:TagSession"]
    }
  ]
}
EOF
```

```bash
cat > grafana-cw-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:DescribeLogGroups", "logs:DescribeLogStreams",
        "logs:GetLogEvents", "logs:FilterLogEvents",
        "logs:StartQuery", "logs:StopQuery", "logs:GetQueryResults",
        "logs:GetLogGroupFields", "logs:GetLogRecord",
        "cloudwatch:ListMetrics", "cloudwatch:GetMetricData",
        "cloudwatch:GetMetricStatistics", "cloudwatch:DescribeAlarmsForMetric",
        "tag:GetResources", "ec2:DescribeRegions"
      ],
      "Resource": "*"
    }
  ]
}
EOF
```
```bash
aws iam create-policy \
  --policy-name wsc2026-grafana-cloudwatch-policy \
  --policy-document file://grafana-cw-policy.json

aws iam create-role \
  --role-name wsc2026-grafana-role \
  --assume-role-policy-document file://grafana-trust.json

aws iam attach-role-policy \
  --role-name wsc2026-grafana-role \
  --policy-arn arn:aws:iam::<ACCOUNTID>:policy/wsc2026-grafana-cloudwatch-policy
```

```bash
aws eks create-addon --cluster-name wsc2026-eks-cluster \
  --addon-name eks-pod-identity-agent --region ap-northeast-2
aws eks wait addon-active --cluster-name wsc2026-eks-cluster \
  --addon-name eks-pod-identity-agent --region ap-northeast-2

kubectl create serviceaccount grafana-sa -n observability

aws eks create-pod-identity-association \
  --cluster-name wsc2026-eks-cluster \
  --namespace observability \
  --service-account grafana-sa \
  --role-arn arn:aws:iam::412869002243:role/wsc2026-grafana-role
```

```bash
kubectl -n observability rollout restart deploy/grafana
```

waf 룰은

commonruleset, sqlruleset, 커스텀 -> 속도 200 레이트 1분