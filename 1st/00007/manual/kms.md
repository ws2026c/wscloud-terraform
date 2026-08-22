app-kms
```json
		{
			"Sid": "Statement1",
			"Effect": "Allow",
			"Action": [
				"kms:Encrypt",
				"kms:Decrypt",
				"kms:ReEncrypt*",
				"kms:GenerateDataKey*",
				"kms:DescribeKey"
			],
			"Resource": "*",
			"Principal": {
				"Service": [
					"dynamodb.amazonaws.com",
					"secretsmanager.amazonaws.com"
				]
			}
		}
```
s3-kms
```json
		{
			"Sid": "Statement1",
			"Effect": "Allow",
			"Action": [
				"kms:Encrypt",
				"kms:Decrypt",
				"kms:ReEncrypt*",
				"kms:GenerateDataKey*",
				"kms:DescribeKey"
				],
			"Resource": "*",
			"Principal": {
				 "Service": [
				 	"s3.amazonaws.com",
				 	"ecr.amazonaws.com",
				 	"cloudfront.amazonaws.com"
				 	]
			}
		}
```
platform-kms
```json
		{
			"Sid": "Statement1",
			"Effect": "Allow",
			"Principal": {
				"Service": [
					"logs.amazonaws.com",
					"eks.amazonaws.com",
					"ec2.amazonaws.com"
				]
			},
			"Action": [
				"kms:Encrypt",
				"kms:Decrypt",
				"kms:ReEncrypt*",
				"kms:GenerateDatakey*",
				"kms:DescribeKey"
			],
			"Resource": "*"
		},
		{
			"Sid": "Statement2",
			"Effect": "Allow",
			"Action": [
				"kms:Decrypt",
				"kms:Encrypt",
				"kms:GenerateDataKey*",
				"dynamodb:Query",
				"dynamodb:GetItem"
				],
			"Resource": "*",
			"Principal": {
				"Service": "lambda.amazonaws.com"
			}
		}
```


eks-cluster 역할 생성 후,
```json
{
	"Version": "2012-10-17",
	"Statement": [
		{
			"Sid": "Statement1",
			"Effect": "Allow",
			"Action": [
				"kms:GenerateDataKey*",
				"kms:CreateGrant",
				"kms:Decrypt",
				"kms:DescribeKey",
				"kms:Encrypt"
			],
			"Resource": [
				"*"
			]
		}
	]
}
```

node 역할 생성 후,
```json
{
	"Version": "2012-10-17",
	"Statement": [
		{
			"Sid": "Statement1",
			"Effect": "Allow",
			"Action": [
				"kms:Decrypt"
			],
			"Resource": [
				"*"
			]
		}
	]
}
```

Lambda 함수 
- 함수 정책에 kms:Decrypt, kms:Encrypt, kms:GenerateDataKey*, dynamodb:Query, dynamodb:GetItem 부여
```json
{
	"Version": "2012-10-17",
	"Statement": [
		{
			"Sid": "Statement1",
			"Effect": "Allow",
			"Action": [
				"kms:Decrypt",
				"kms:Encrypt",
				"kms:GenerateDataKey*",
				"dynamodb:Query",
				"dynamodb:GetItem"],
			"Resource": ["*"]
		}
	]
}
```

- Platform KMS에 (”Service”: “lambda.amazonaws.com”) 를 대상으로 위와 같은 권한 부여(platform kms json에 포함)

WAF KMS 정책 (복제된 us-east-1에서 진행)
```json
{
  "Version": "2012-10-17",
  "Id": "key-consolepolicy-3",
  "Statement": [
    {
      "Sid": "Enable IAM User Permissions",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::<계정ID>:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "ACL Permissions",
      "Effect": "Allow",
      "Principal": {
        "Service": "logs.us-east-1.amazonaws.com"
      },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    }
  ]
}
```
