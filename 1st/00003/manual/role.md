AdiminsistratorAccess 정책 가진 IAM 사용자 생성, 로그인 \
mark-sg 보안 그룹 생성\

1 lambda policy : DynamoDB에 대해 Query 허용
2 Deployment Pod Policy : DynamoDB에 대해 PutItem 허용

2-2 Deployment Pod Role 신뢰 관계
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowEKSIdentity",
            "Effect": "Allow",
            "Principal": {
                "Service": "pods.eks.amazonaws.com"
            },
            "Action": [
                "sts:AssumeRole",
                "sts:TagSession"
            ]
        }
    ]
}
```

3 Container Orchestration Node Role 미리 생성\
사용 사례 EC2\
Name : AmazonEKSNodeRole\
- AmazonEC2ContainerRegistryReadOnly
- AmazonEKsWorkerNodePolicy
- AmazonEKS_CNI_Policy
- AmazonSSMManagedInstanceCore
