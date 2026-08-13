# 전국대회 2과제 00007 배포가이드

## 2) CDN Function (us-east-1)
- 리전 변경 (us-east-1, 버지니아 북부.)

1. CDN 구성
    - S3 Bucket Name : skillsphone-landing-ab-<ACCOUNT_ID 12자리>
    - index_a.html 파일 업로드 : /version-a/index.html
    - index_b.html 파일 업로드 : /version-b/index.html \
    버킷 버전 관리 활성화 및 버킷 정책에서 Condition의 ArnLike 부분을 StringEquals로 바꿔주기    
### index_a.html과 index_b.html의 파일 이름을 index.html로 각각 폴더에 넣어주기

2. KeyValueStore 구성
    - AWS 콘솔 기준 CloudFront 접속 -> 함수(Functions) -> KeyValueStores
    - KeyValueStore Name : skillsphone-cdn-ab-config
    - 생성 후
    - key value pairs -> Edit
        - weight : 0.3
        - version_b : /version-b/index.html
        - version_a : /version-a/index.html
    - 위 처럼 설정

3. Cloudfront Function 구성
    - Viewer Request Function Name : skillsphone-cdn-ab-req-fn
    - Viewer Response Function Name : skillsphone-cdn-ab-res-fn
        - 생성 후 Request Function(skillsphone-cdn-ab-req-fn)에 접속 후 Associated KeyValueStore을 방금 만든 skillsphone-cdn-ab-config 연결 해주기
    - Function 함수들의 코드는 github에 req.js와 res.js 참고하기\
    함수 코드 다 작성 시, 게시 탭에서 함수 게시해주기

4. Policy 구성
    - Cache Policy Name : skillsphone-cdn-ab-cache-policy
    - Min/Default/Max TTL : 0 / 300 / 3600
    - Cookies : whitelist (x-sp-ab)
        - 정책 -> 캐시 -> 캐시 정책 생성
        - skillsphone-cdn-ab-cache-policy 이름 설정\
        TTL 설정은 최소 TTL : 0, 최대 TTL : 3600, 기본 TTL : 300\
        헤더 - 없음. 쿠키 - 지정된 쿠키 포함 : x-sp-ab, 쿼리 문자열 - 없음 \
        압축 지원 둘 다 활성화
    - 정책 -> 응답 헤더 -> 응답 헤더 정책 생성
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

5. CloudFront Distribution 구성
    - Pay as you go로 CloudFront 배포
    - Distribution Name : skillsphone-cdn-ab-distribution
    - Description : skillsphone-cdn-ab-distribution
    - Origin -> S3 origin -> Browse S3 -> 만들어둔 S3 선택
    - WAF -> 보안 보호 비활성화 -> Create
    - 배포된 cloudfront -> 원본 -> 만들어진 거 편집
        - 원본 엑세스 -> 원본 엑세스 제어 설정
    - 배포된 cloudfront -> 동작 -> 만들어진 거 편집
        - 뷰어 프로토콜 정책 -> Redirect HTTP to HTTPS
        - 캐시 정책 -> skillsphone-cdn-ab-cache-policy\
        원본 요청 정책 -> 선택 안함\
        응답 헤더 정책 -> 만들어둔 거(예시 : skillsphone-cdn-security-headers-policy)
        - 함수 연결\
        뷰어 요청 -> CloudFront Functions -> skillsphone-cdn-ab-req-fn\
        뷰어 응답 -> CloudFront Functions -> skillsphone-cdn-ab-res-fn
    - 저장
