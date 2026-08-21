### 아래 역할과 정책들은 KMS 생성 전 미리 생성

- Lambda Role 및 Lambda Policy (DynamoDB에 대해 Query 허용)
- Deployment Role 및 Deployment Policy (DynamoDB에 PutItem 허용)
  **신뢰 관계**
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

- EKS에서 NodeRole도 미리 생성하는 것이 좋음. 노드그룹 생성 시 자동으로 연결되는 정책과 이름으로 생성
