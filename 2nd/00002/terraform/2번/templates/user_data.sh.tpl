#!/bin/bash
set -x
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "=== 1. Python 설치 ==="
dnf -y install python3.12 python3.12-pip || true
if command -v python3.12 >/dev/null 2>&1; then
  PY=$(command -v python3.12)
else
  dnf -y install python3-pip
  PY=$(command -v python3)
fi
echo "python: $PY ($($PY --version))"

echo "=== 2. 배포파일 배치 (/opt/app) ==="
mkdir -p /opt/app
echo "${app_py_b64}" | base64 -d > /opt/app/app.py
echo "${requirements_b64}" | base64 -d > /opt/app/requirements.txt
chmod 644 /opt/app/app.py /opt/app/requirements.txt

echo "=== 3. 가상환경 + 의존성 설치 ==="
$PY -m venv /opt/app/venv
/opt/app/venv/bin/pip install --upgrade pip
for i in 1 2 3; do
  /opt/app/venv/bin/pip install -r /opt/app/requirements.txt && break
  echo "pip install retry $i"
  sleep 10
done

echo "=== 4. systemd 서비스 등록 (서비스명: app) ==="
cat > /etc/systemd/system/app.service <<'UNIT'
[Unit]
Description=WSC2026 Analytics Order Log Application
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/app
Environment="STREAM_NAME=${stream_name}"
Environment="AWS_REGION=${region}"
Environment="AWS_DEFAULT_REGION=${region}"
ExecStart=/opt/app/venv/bin/gunicorn --chdir /opt/app --bind 0.0.0.0:${app_port} --workers 2 --timeout 60 app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable app
systemctl restart app
sleep 3
systemctl is-active app
systemctl is-enabled app

echo "=== 5. 헬스체크 ==="
for i in 1 2 3 4 5; do
  curl -sf http://127.0.0.1:${app_port}/health && break
  sleep 3
done
echo "=== user-data 완료 ==="
