# 00008 - Mod2

- VPC 생성
  - skills-lattice-client-vpc는 Private Subnet이 포함되지 않아도 됨
  - skills-lattice-service-vpc는 Private Subnet 구성 및 NAT G/W는 1개 이상 자유 구성

- EC2 설정
  - 문제지 참고하여 EC2 생성 (인스턴스 유형은 t3.micro 사용 권장, 보안 그룹 구성 중요)
  - skills-lattice-service-ec2에는 AmazonSSMManagedInstanceCore 정책 붙이기
  - skills-lattice-service-ec2는 퍼블릭 IP가 없기 때문에 SSM으로 연결하여 접근할 것
    - SSM 접근 이후 sudo su - ec2-user 입력 후 작업
  - sudo dnf install -y python3-pip 으로 Python 반드시 설치
  - EC2마다 애플리케이션을 /opt/app/ 에 올리기

  **Client EC2 Systemd**
  - systemctl start 및 enable 필요
  - 예) 저장 경로 /etc/systemd/system/client.service
  ```toml
  [Unit]
  Description=Client svc
  
  [Service]
  Type=simple
  ExecStart=python3 /opt/app/client_app.py
  Restart=on-failure
  Environment="SERVICE_URL="
  StandardOutput=file:/var/log/client.log
  StandardError=file:/var/log/client.log
  
  [Install]
  WantedBy=multi-user.target
  ```
    **Service EC2 Systemd**
  - systemctl start 및 enable 필요
  - 예) 저장 경로 /etc/systemd/system/service.service
  ```toml
  [Unit]
  Description=Service svc
  
  [Service]
  Type=simple
  ExecStart=python3 /opt/app/service_app.py
  Restart=on-failure
  StandardOutput=file:/var/log/service.log
  StandardError=file:/var/log/service.log
  
  [Install]
  WantedBy=multi-user.target
  ```
