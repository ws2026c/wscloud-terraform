# 2) 전국대회 2과제
### 00002 Real-time Data Analytics(ap-northeast-2,서울) 

**1 vpc 제작**
- 요구사항 따라서 VPC 제작

**2 보안 그룹 2개**

### `alb-sg`
- 인바운드: HTTP 80 ← 0.0.0.0/0

### `ec2-sg`
- 인바운드: 사용자 지정 TCP **5000** ← 소스: `alb-sg`

---

**3 IAM 역할 (EC2용)**

**IAM → 역할 생성 → AWS 서비스 → EC2**

- 이름: `wsc2026-analytics-ec2-role`
- 정책: `AmazonSSMManagedInstanceCore`, `AmazonKinesisFullAccess`

---

**4 Kinesis**

**Kinesis → 데이터 스트림 생성**

- 이름: `wsc2026-order-stream`
- 용량 모드: **온디맨드** → 생성

---

**5 EC2**

**EC2 → 인스턴스 시작**

- 이름: `wsc2026-analytics-ec2`
- AMI: **Amazon Linux 2023**
- 유형: **t3.small**
- 키 페어: 없이 진행 (SSM 접속)
- 네트워크: analytics-vpc / 서브넷 **analytics-priv-a** / 퍼블릭 IP **비활성화**
- 보안 그룹: `ec2-sg`
- 고급 → IAM 인스턴스 프로파일: `wsc2026-alaytics-ec2-role`
- 고급 → 사용자 데이터에 붙여넣기:

```bash
#!/bin/bash
dnf -y install python3.12
mkdir -p /opt/app
python3.12 -m venv /opt/app/venv
/opt/app/venv/bin/pip install flask boto3 gunicorn
cat > /etc/systemd/system/app.service <<'EOF'
[Unit]
Description=order app
After=network-online.target
[Service]
WorkingDirectory=/opt/app
Environment="STREAM_NAME=wsc2026-order-stream"
Environment="AWS_REGION=ap-northeast-2"
ExecStart=/opt/app/venv/bin/gunicorn --chdir /opt/app -b 0.0.0.0:5000 app:app
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable app
systemctl start app
```

후에 SSM으로 인스턴스 접속\
sudo su - \
cat > /opt/app/app.py <<'PYEOF'\
(app.py 내용 붙여넣기)\
PYEOF\
systemctl restart app
- 점검 하고자 한다면 systemctl is-active app && curl -s localhost:5000/health

확인 (Session Manager):
```
systemctl is-active app     → active
systemctl is-enabled app    → enabled
curl localhost:5000/health  → {"status":"healthy"}
```

---

**6 대상 그룹 + ALB**

**EC2 → 대상 그룹 → 생성**

- 유형: 인스턴스 / 이름: `wsc2026-analytics-tg`
- 프로토콜: HTTP **5000** / VPC: analytics-vpc
- 상태 검사 경로: `/health`
- 대상 등록: wsc2026-analytics-ec2 → 포트 5000 → 생성

**EC2 → 로드 밸런서 → ALB 생성**


---

**7 Managed Flink Studio**

**Managed Apache Flink → Studio 노트북 → Studio 노트북 생성**

- **빠른 설정으로 생성** 선택 (Glue DB·역할 자동 생성 → 제일 편함)
- 이름: `wsc2026-analytics-flink`
- 런타임이 **Apache Flink 1.15, Apache Zeppelin 0.10 (ZEPPELIN-FLINK-3_0)** 인지 확인 → 생성
- Glue Database -> 그냥 아무 이름으로 생성해서 연결( 예시 : wsc2026_db)