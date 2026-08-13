# 00007 - Mod1

**반드시 문제지와 같이**
- 문제지 조건대로 테이블(Reservation 및 Audit 테이블)을 모두 생성
  - Reservation Table 생성 후 PITR 활성화 및 DynamoDB 스트림 활성화 (새 이미지와 이전 이미지)
1. Lambda 함수 구성 (3. Streams 처리 구성)
   - 배포파일에서 함수 내용을 그대로 가져오기
   - Lambda 실행 역할에는 dynamodb의 GetItem, Query, PutItem, GetRecords, GetShardIterator, DescribeStream, ListStreams 권한 부여
   - 권한 부여 이후 DynamoDB 트리거와 연결
   - 핸들러의 경우 lambda_function.lambda_handler 가 아닌 lambda_function.handler
   - 제한 시간은 구성에서 설정 가능 3초 -> 30초
2. EC2 구성 (2. Conditional Write 및 4. 구성)
   - VPC (기본 VPC 권장) 및 문제지에 제시된 EC2 생성 (이름 외 자유구성)
   - EC2는 8080에서 외부로부터 접근 가능해야함
   - EC2 Role 권한 : dynamodb의 Query, PutItem, UpdateItem, Scan
   - 배포파일 (app.py 및 requirements.txt를 EC2에 전송)
     ```bash
     sudo dnf install -y python3-pip
     sudo python3 -m pip install -r requirements.txt
     ```
   - 앱을 /opt/app/ 등의 경로로 이동 및 적절한 권한 부여 후 아래 systemd 파일 작성 및 실행, 활성화
     ```toml
     [Unit]
     Description=ec2 service
     
     [Service]
     Type=simple
     Environment=AWS_REGION=ap-southeast-1
     Environment=TABLE_NAME=bigbae-nosql-reservation-table
     Environment=gsi-user-reservations
     ExecStart=python3 /opt/app/app.py
     Restart=on-failure
     StandardOutput=file:/var/log/app.log
     StandardError=file:/var/log/app.log
     
     [Install]
     WantedBy=multi-user.target
     ```
   - 구성한 인프라가 모두 작동되는지 확인
