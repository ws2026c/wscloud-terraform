모든 키의 키 관리자를 본인의 IAM 사용자로 지정

1. wsc2026-db-kms
wsc2026-book-function-role, wsc2026-book-pod-role를 Principal로 하여 다음 키 권한 부여
  ```json
"kms:Encrypt",
"kms:Decrypt",
"kms:ReEncrypt*",
"kms:GenerateDataKey*",
"kms:DescribeKey"
```
2. wsc2026-ecr-kms
AmazonEKSNodeRole를 Principal로 하여 다음 키 권한 부여
```json
"kms:Decrypt",
"kms:DescribeKey"
```
3. wsc2026-eks-kms
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
4. wsc2026-bucket-kms
	1. 키 관리자로 지정하여 기본 생성된 권한에 추가로 부여
		```json
		"kms:Decrypt",
		"kms:GenerateDataKey*"
		```
	
	2. "Service":"cloudfront.amazonaws.com"을 Principal로 하여 다음 권한 부여
		```json
		"kms:Decrypt"
		```
5. wsc2026-function-kms
	1. 키 관리자로 지정하여 기본 생성된 권한에 추가로 부여
		```json
		"kms:Decrypt",
		"kms:GenerateDataKey*",
		"kms:Encrypt"
		```
	2. wsc2026-book-function-role을 Principal로 하여 다음 권한 부여
		```json
		"kms:Encrypt",
		"kms:Decrypt",
		"kms:GenerateDataKey*",
		"kms:DescribeKey"
		```
	3. "Service":"lambda.amazonaws.com"를 Principal로 하여 다음 권한 부여
		```json
		"kms:Encrypt",
		"kms:Decrypt",
		"kms:GenerateDataKey*",
		"kms:DescribeKey"
		```
