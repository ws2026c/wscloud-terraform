# 00008 - Mod2 Terraform 수동 메뉴얼

- skills-lattice-client-ec2에 웹 콘솔에서 SSH로 접근
- skills-lattice-service-ec2에 SSM Session Manager로 접근

**공통 설정**
sudo dnf install -y python3-pip
/opt/app/ 에 배포파일 올리기
아래 systemd 적용 후 시작 & enable

**skills-lattice-client-ec2 System daemon file**
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

**skills-lattice-service-ec2 System daemon file**
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
