# 전국대회 2과제 00008 배포가이드

## 3) Cloud Event Handing (ap-southeast-1, 싱가포르)
1.  VPC, EC2 
    - VPC Name과 CIDR 준수, 프라이빗 서브넷 불필요. 퍼블릭 서브넷 생성
    - 생성한 퍼블릭 서브넷에 ec2 배치.\
    ec2는 키 페어 필요 없으며, skills-ceh-protected-sg(인바운드 없는 보안그룹) 연결
### skills-ceh-protected-sg는 Name Tag임 태그를 통해 Name : skills-ceh-protected-sg

2. SNS Topic
    - 아마존 콘솔 SNS -> 주제 생성(이름과 타입 준수 생성)\
    이외 건들 내용 X

3. Lambda
    - 요구사항 따라 function 제작.\
    function IAM 역할의 경우
        - 새 역할 생성 -> 추가 정책 -> 새 정책 생성\
        git hub, lambda-policy.js 참고
    - 코드에서 lambda_function.py -> remediate_security_group.py로 변경 및 배포파일 내용 붙여넣기. Deploy
    - 런타임 설정에서 핸들러 -> 이전 내용 삭제 -> remediate_security_group.lambda_handler로 변경
    - 구성 -> 일반 구성 -> Time Out 시간 30초 이상
    - 구성 -> 환경 변수 -> 과제지 요구대로 환경 변수 두 개 생성

4. EventBridge Rule
    - CloudTrail -> 추적 -> 추적 생성\
    이름은 과제지 요구대로(skills-ceh-cloudtrail)\
    스토리지 -> 새 S3 버킷 생성\
    로그 파일 암호화 -> 체크 해제
    이벤트 유형 : 관리 이벤트 체크 -> API 활동 : 읽기 + 쓰기 반드시 포함.
    - 생성 후 Logging:Enabled 확인 후 다음

5. EventBridge Rule
    - 규칙 -> 규칙 생성 -> 고급 빌더 -> 이름 요구사항 대로, 이벤트 버스 요구 사항 대로\
    이벤트 패턴 -> 사용자 지정 패턴\
    {
  "source": ["aws.ec2"],
  "detail-type": ["AWS API Call via CloudTrail"],
  "detail": {
    "eventSource": ["ec2.amazonaws.com"],
    "eventName": ["AuthorizeSecurityGroupIngress"]
  }
}
    - 대상 -> AWS 서비스 -> Lambda 함수 -> 만들어 진거 선택\
    ### lambda로 넘어가서 구성 -> 권한 -> 리소스 기반 정책 설명 -> 권한 추가
    AWS 서비스 ->EventBridge  문 ID(아무거나), 보안 주체 events.amazonaws.com(기본값)\
    소스 ARN은 EventBridge Rule의 규칙 ARN\
    작업은 lambda:InvokeFunction
