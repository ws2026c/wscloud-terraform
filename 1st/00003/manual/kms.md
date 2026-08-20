1. db-kms\
wsc2026-book-function-role, wsc2026-book-pod-role에 다음 권한 부여
  ```json
"kms:Encrypt",
"kms:Decrypt",
"kms:ReEncrypt*",
"kms:GenerateDataKey*",
"kms:DescribeKey"
```
2. ecr-kms\
AmazonEKSNodeRole에 다음 권한 부여
```json
"kms:Decrypt",
"kms:DescribeKey"
```
3. eks-kms\
```json
{
	"Version": "2012-10-17",
	"Statement": [
		{
			"Sid": "AllowAdminManagement",
			"Effect": "Allow",
			"Principal": {
				"AWS": "arn:aws:iam::<AccountID>:user/<UserID>"
			},
			"Action": [
				"kms:Create*",
				"kms:Describe*",
				"kms:Enable*",
				"kms:List*",
				"kms:Put*",
				"kms:Update*",
				"kms:Revoke*",
				"kms:Disable*",
				"kms:Get*",
				"kms:Delete*",
				"kms:TagResource",
				"kms:UntagResource",
				"kms:ScheduleKeyDeletion",
				"kms:CancelKeyDeletion"
			],
			"Resource": "*"
		},
		{
			"Sid": "AllowEKSServiceAndRoleUse",
			"Effect": "Allow",
			"Principal": {
				"AWS": "arn:aws:iam::<AccountID>:role/AmazonEKSClusterRole"
			},
			"Action": [
				"kms:Encrypt",
				"kms:Decrypt",
				"kms:ReEncrypt*",
				"kms:GenerateDataKey*",
				"kms:DescribeKey",
				"kms:CreateGrant"
			],
			"Resource": "*"
		},
		{
			"Sid": "AllowCloudWatchLogsService",
			"Effect": "Allow",
			"Principal": {
				"Service": "logs.ap-northeast-2.amazonaws.com"
			},
			"Action": [
				"kms:Encrypt*",
				"kms:Decrypt*",
				"kms:ReEncrypt*",
				"kms:GenerateDataKey*",
				"kms:Describe*"
			],
			"Resource": "*",
			"Condition": {
				"ArnLike": {
					"kms:EncryptionContext:aws:logs:arn": "arn:aws:logs:ap-northeast-2:<AccountID>:log-group:/aws/eks/wsc2026-eks-cluster/cluster"
				}
			}
		}
	]
}
```
4. s3-kms\
키 관리자(유저)에 다음 권한도 추가 부여
```json
"kms:Decrypt",
"kms:GenerateDataKey*"
```
"Service":"cloudfront.amazonaws.com"에 다음 권한 부여
```json
"kms:Decrypt"
```
5. lambda-kms \
키 관리자(유저)에 다음 권한도 추가 부여
```json
"kms:Decrypt",
"kms:GenerateDataKey*",
"kms:Encrypt"
```
wsc2026-book-function-role 및 "Service":"lambda.amazonaws.com"에 다음 권한 부여
```json
"kms:Encrypt",
"kms:Decrypt",
"kms:GenerateDataKey*",
"kms:DescribeKey"
```

