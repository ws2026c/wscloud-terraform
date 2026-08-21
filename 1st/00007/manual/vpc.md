vpc flow logs\
신뢰 정책

```json
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {
            "Service": "vpc-flow-logs.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
    }]
}
```

정책
```json
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents",
            "logs:DescribeLogGroups",
            "logs:DescribeLogStreams"
        ],
        "Resource": "*"
    }]
}
```

역할 미리 생성 후 플로우 로그.


로그 그룹 /unicorn/vpc

엔드포인트

s3,ecr.dkr,ecr.api
https -> 10.97.0.0/16 인바운드 보안 그룹(따로 제작)
