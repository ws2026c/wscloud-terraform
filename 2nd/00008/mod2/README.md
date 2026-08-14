# 00008 - Mod2

- VPC 생성
  - skills-lattice-client-vpc는 Private Subnet이 포함되지 않아도 됨
  - skills-lattice-service-vpc는 Private Subnet 구성 및 NAT G/W는 1개 이상 자유 구성

- EC2 설정
  - 문제지 참고하여 EC2 생성 (인스턴스 유형은 t3.micro 사용 권장, 보안 그룹 구성 중요)
  - skills-lattice-service-ec2에는 AmazonSSMManagedInstanceCore 정책 붙이기
  - skills-lattice-service-ec2는 퍼블릭 IP가 없기 때문에 SSM으로 연결하여 접근할 것 (보안 그룹에 SSH 인바운드 제거)
    - SSM 접근 이후 sudo su - ec2-user 입력 후 작업
  - sudo dnf install -y python3-pip 으로 Python 반드시 설치
  - EC2마다 애플리케이션을 /opt/app/ 에 올리기

  **Client EC2 Systemd** (Lattice 생성 후 반영하는 것을 권장)
  - systemctl start 및 enable 필요
  - 예) 저장 경로 /etc/systemd/system/client.service
  ```toml
  [Unit]
  Description=Client svc
  
  [Service]
  Type=simple
  ExecStart=python3 /opt/app/client_app.py
  Restart=on-failure
  Environment="SERVICE_URL=http://<Lattice 주소>"
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

- Lattice 설정
  - 서비스 네트워크 생성
    - 서비스와 연결해야 하지만 나중에 자동으로 연결되므로 패스
    - VPC 연결의 경우 skills-lattice-client-vpc를 대상으로 하며, 보안 그룹도 문제지 참고
    - 다른 항목은 건들필요 없음
  - Lattice 서비스 설정
    - 리스너와 대상 그룹은 문제지를 참고하여 생성
    - 리스너의 포트는 80, 대상 그룹의 포트는 8080 이여야 함.
    - 위에서 만든 서비스 네트워크랑 연결하면 끝
