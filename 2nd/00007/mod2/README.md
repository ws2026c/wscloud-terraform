버킷 버전 관리 활성화 및 버킷 정책에서 Condition의 ArnLike 부분을 StringEquals로 바꿔주기    

    - 응답 헤더 정책 생성
        - 이름은 상관 없음( 예시 : skillsphone-cdn-security-headers-policy)\
        보안헤더
            - Strict-Transport-Security
                - 최대 기간 : 31536000, 미리 로드 활성화, includeSubDomains 활성화
            - X-Content-Type-Options
            - X-Frame-Options
                - 원본 DENY
            - X-XSS-Protection
                - X-XSS-Protection 활성화됨, 차단 활성화, 보고서 작성 X
            - Referrer-Policy
                - strict-origin-when-cross-origin
            - Content-Security-Policy
                - Content-Security-Policy \
                default-src 'self'; img-src 'self' data: https:; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; font-src 'self' data:; object-src 'none'; frame-ancestors 'none'
            - 위 전부 오리진 재정의 활성화 -> 저장

    - WAF -> 보안 보호 비활성화 -> Create
    - 배포된 cloudfront -> 원본 -> 만들어진 거 편집
        - 원본 엑세스 -> 원본 엑세스 제어 설정
    - 배포된 cloudfront -> 동작 -> 만들어진 거 편집
        - 캐시 정책 -> skillsphone-cdn-ab-cache-policy\
        응답 헤더 정책 -> 만들어둔 거
        request CloudFront Functions -> skillsphone-cdn-ab-req-fn\
        response  CloudFront Functions -> skillsphone-cdn-ab-res-fn
