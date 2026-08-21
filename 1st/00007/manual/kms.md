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
					"lambda.amazonaws.com",
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
		}
```
