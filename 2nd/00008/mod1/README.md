# Initial Commit

문제지 순서대로 풀이

1. VPC 서브넷은 퍼블릭 2 프라이빗 2 (NAT 불필요)으로 구성
2. EC2는 t3.micro 또는 t3.small 정도로 생성
3. EC2에 SecretManagerReadWrite 권한 부여하기
4. EC2의 /opt/skills-nosql/ 경로에 배포파일을 모두 업로드해야 함. (홈 디렉터리에 가져오고 chmod로 권한을 주고 mv)
5. Systemd로 서비스 구성 (enable 시키기,  경로 : /etc/systemd/system/skills.service)
   ```toml
    [Unit]
    Description=skills
    
    [Service]
    Type=simple
    ExecStart=/opt/skills-nosql/docdb_client.py
    WorkingDirectory=/opt/skills-nosql
    Restart=on-failure
    StandardOutput=file:/var/log/skills.log
    StandardError=file:/var/log/skills.log
    
    [Install]
    WantedBy=multi-user.target
   ```
7. 외부에서 EC2에 8080포트로 접근 가능해야함
8. DB 생성 전 서브넷, 보안, 파라미터 그룹을 생성 (TLS 옵션은 파라미터 그룹에서 활성화 가능)
9. 엔진버전은 기본값인 5.0.0, 인스턴스 개수는 1대만 유지해도 무방
10. DocumentDB 콘솔에서 global_bundle.pem을 다운로드 할 수 있으며 이것도 /opt/skills-nosql/ 에 옮기기
