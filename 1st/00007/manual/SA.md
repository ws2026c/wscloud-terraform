Service Account
IAM 콘솔에서 kms:Decrypt, dynamodb:PutItem을 허용하는 정책 생성.

```bash -> 신뢰관계 생성
cat <<EOF > trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "pods.eks.amazonaws.com"
      },
      "Action": [
        "sts:AssumeRole",
        "sts:TagSession"
      ],
      "Condition": {
        "StringEquals": {
          "aws:SourceAccount": "${AWS_ACCOUNT_ID}"
        },
        "ArnEquals": {
          "aws:SourceArn": "arn:aws:eks:${AWS_DEFAULT_REGION}:${AWS_ACCOUNT_ID}:cluster/${CLUSTER_NAME}"
        }
      }
    }
  ]
}
EOF
```

정책 생성
```bash
aws iam create-role \
  --role-name "unicorn-pod-identity-role" \
  --assume-role-policy-document file://trust-policy.json \
  --description "Pod Identity Role"

aws iam attach-role-policy \
  --role-name "unicorn-pod-identity-role" \
  --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/<정책이름>"
```

Pod Identity 연결
```bash
aws eks create-pod-identity-association \
  --cluster-name unicorn-eks-cluster \
  --namespace unicorn \
  --service-account unicorn-book-app-sa \
  --role-arn arn:aws:iam::$AWS_ACCOUNT_ID:role/unicorn-pod-identity-role
```
