# 00008 - Mod1

1. VPC 서브넷은 퍼블릭 2 프라이빗 2 (NAT 불필요)으로 구성
2. EC2는 t3.micro 또는 t3.small 정도로 생성
3. EC2에 SecretManagerReadWrite 권한 부여하기
4. EC2의 /opt/skills-nosql/ 경로에 배포파일을 모두 업로드해야 함. (홈 디렉터리에 가져오고 chmod로 권한을 주고 mv)
5. 아래 명령어로 파이썬 설치
   - sudo dnf install -y python3-pip
   - sudo python3 -m pip install pymongo boto3
7. Systemd로 서비스 구성 (enable 시키기,  경로 : /etc/systemd/system/skills.service)
   ```toml
   [Unit]
   Description=skills
   
   [Service]
   Type=simple
   ExecStart=python3 /opt/skills-nosql/docdb_client.py serve
   WorkingDirectory=/opt/skills-nosql
   Restart=on-failure
   StandardOutput=file:/var/log/skills.log
   StandardError=file:/var/log/skills.log
   
   [Install]
   WantedBy=multi-user.target
   ```
8. 외부에서 EC2에 8080포트로 접근 가능해야함
9. DB 생성 전 서브넷, 보안, 파라미터 그룹을 생성 (TLS 옵션은 파라미터 그룹에서 활성화 가능)
  - 기본 파라미터 그룹이 존재하면 기본 파라미터 그룹 사용
10. 엔진버전은 기본값인 5.0.0, 인스턴스 개수는 1대만 유지해도 무방
10-1. KMS 생성의 경우 별칭에 alias/ 를 포함하지 말 것. 
11. 인스턴스 이름은 생성 이후에 변경 가능 / 인증 정보의 경우 Self managed
12. DocumentDB 콘솔에서 global_bundle.pem을 다운로드 할 수 있으며 이것도 /opt/skills-nosql/ 에 옮기기
13. Secret Manager 먼저 생성
14. /opt/skills-nosql/ 로 가서 `python3 docdb_client.py seed` 를 실행하여 데이터 적재
15. 아래 파이썬 파일을 저장 후 실행 (데이터 구조를 변경할 임시 스크립트이므로 사용 후 삭제)
    - python3 <파일명>.py 로 실행
    ```python
    import boto3
    from pymongo import MongoClient, ASCENDING, DESCENDING
    
    session = boto3.session.Session(region_name="ap-northeast-2")
    
    uri = f"mongodb://<유저명:패스워드>@<엔드포인트>:27017/?replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false"
    db = MongoClient(uri, tls=True, tlsCAFile="/opt/skills-nosql/global-bundle.pem")["skills_retail"]
    
    db.orders.create_index([("orderId", ASCENDING)], unique=True)
    db.orders.create_index([("customerId", ASCENDING), ("createdAt", DESCENDING)])
    db.orders.create_index([("status", ASCENDING), ("dueAt", ASCENDING)])
    
    db.products.create_index([("productId", ASCENDING)], unique=True)
    db.products.create_index([("warehouseId", ASCENDING), ("stock", ASCENDING)])
    
    db.sessions.create_index([("sessionId", ASCENDING)], unique=True)
    db.sessions.create_index([("expiresAt", ASCENDING)], expireAfterSeconds=0)
    db.sessions.create_index([("customerId", ASCENDING), ("lastSeen", DESCENDING)])
    ```
16. EC2 Public IP에 접속하여 잘 실행되는지 확인
