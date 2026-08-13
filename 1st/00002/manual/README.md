# 00002 - 1과제

과제지 순서대로 풀이 진행

- S3 유의 사항
    - 채점 시 폴더 객체가 포함되지 않도록 로컬에서 미리 `web/main` 폴더를 생성하고 그 안에 정적 파일들을 넣어 한번에 업로드

- ECR 유의사항
    - KMS 관리형 키 또는 KMS CMK 사용
    - Dockerfile
        ```Docker
        FROM alpine:latest

        EXPOSE 8080

        COPY book .

        RUN chmod +x book

        CMD ["./book"]
        ```
- NoSQL Database 요구사항 추가
    - GSI Name / PK,SK : concert_name-created_at-index / concert_name(PK), created_at(SK) 조건 추가

- EKS 설정 방법
    - 사전에 생성한 `wskorea26-vpc-environment-sg` 보안그룹의 443 인바운드를 허용하는 추가 보안 그룹 생성
    - KMS 암호화 방법 : 봉투 암호화 활성화
    - 추가 기능 : CoreDNS, Kube-Proxy, VPC CNI
    - 시작 템플릿 
        - 리소스 태그(Name) 설정
        - 메타데이터 응답 홉 제한 2 이상
    - Bottle Rocket이나 Amazon Linux 2023 사용

- EKS 노드 그룹 설정
    - App
