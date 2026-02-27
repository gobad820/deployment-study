# GitHub Actions 워크플로우 설명

## 현재 워크플로우 분석

```yaml
# .github/workflows/deploy.yml
name: Deploy to EC2

on:
  push:
    branches: [ "main" ]   # main 브랜치에 push 시 자동 실행

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      # 1. 소스코드 체크아웃
      - uses: actions/checkout@v4

      # 2. JDK 21 설치
      - name: Set up JDK 21
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '21'

      # 3. Gradle 의존성 캐싱 (빌드 속도 향상)
      - name: Gradle Caching
        uses: actions/cache@v3
        with:
          path: |
            ~/.gradle/caches
            ~/.gradle/wrapper
          key: ${{ runner.os }}-gradle-${{ hashFiles('**/*.gradle*', '**/gradle-wrapper.properties') }}

      # 4. GitHub Secrets에서 application.properties 생성
      - name: Create application.properties
        run: |
          mkdir -p ./src/main/resources
          echo "${{ secrets.APPLICATION_PROPERTIES }}" > ./src/main/resources/application.properties

      # 5. Gradle로 빌드 (테스트 제외)
      - name: Build with Gradle
        run: ./gradlew clean build -x test

      # 6. SCP로 JAR 파일을 EC2에 전송
      - name: Transfer Jar to EC2
        uses: appleboy/scp-action@master
        with:
          host: ${{ secrets.EC2_HOST }}
          username: ubuntu
          key: ${{ secrets.EC2_PRIVATE_KEY }}
          source: "./build/libs/*.jar"
          target: "/home/ubuntu/app"
          strip_components: 2   # build/libs/ 경로를 제거하고 파일만 전송

      # 7. SSH로 deploy.sh 실행
      - name: Deploy
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ secrets.EC2_HOST }}
          username: ubuntu
          key: ${{ secrets.EC2_PRIVATE_KEY }}
          script: |
            chmod +x /home/ubuntu/deploy.sh
            /home/ubuntu/deploy.sh
```

## GitHub Secrets 설정

GitHub 저장소 → Settings → Secrets and variables → Actions 에서 등록:

| Secret 이름 | 내용 |
|------------|------|
| `EC2_HOST` | EC2 퍼블릭 IP 또는 도메인 |
| `EC2_PRIVATE_KEY` | EC2 접속용 `.pem` 파일 내용 전체 |
| `APPLICATION_PROPERTIES` | `application.properties` 파일 내용 |

### EC2_PRIVATE_KEY 등록 방법

```bash
# 로컬에서 pem 파일 내용 복사
cat your-key.pem
```

`-----BEGIN RSA PRIVATE KEY-----` 부터 `-----END RSA PRIVATE KEY-----` 까지 전체를 복사해서 Secrets에 등록.

## 전체 실행 흐름

```
1. main 브랜치 push
    │
2. GitHub Actions Runner 실행 (ubuntu-latest VM)
    │
3. 소스코드 체크아웃
    │
4. JDK 21 설치 + Gradle 캐시 복원
    │
5. application.properties 생성 (Secrets 값으로)
    │
6. ./gradlew clean build -x test
    └── build/libs/deploymnet-study-0.0.1-SNAPSHOT.jar 생성
    │
7. SCP: JAR 파일을 EC2의 /home/ubuntu/app/ 로 전송
    │
8. SSH: /home/ubuntu/deploy.sh 실행
    └── Blue-Green 배포 진행 (03-deploy-script.md 참고)
```

## strip_components: 2 옵션 설명

```yaml
source: "./build/libs/*.jar"
target: "/home/ubuntu/app"
strip_components: 2
```

- `strip_components: 2`가 없으면: EC2에 `/home/ubuntu/app/build/libs/app.jar` 로 전송됨
- `strip_components: 2`가 있으면: `build/libs/` 2단계를 제거하고 `/home/ubuntu/app/app.jar` 로 전송됨

## -x test 플래그

```bash
./gradlew clean build -x test
```

`-x test`: 테스트 단계를 건너뜀.

- 빌드 시간 단축
- 단, 테스트를 건너뛰므로 품질 위험이 있음
- 실무에서는 별도 테스트 job을 먼저 실행하고 통과 시 배포 job을 실행하는 패턴을 사용

## 워크플로우 개선 포인트 (참고)

현재 워크플로우에서 `Debug - Check File List` step이 있다. 디버깅용으로 추가된 것이므로 실제 운영에서는 제거해도 된다.

```yaml
# 이 step은 제거 가능
- name: Debug - Check File List
  run: ls -R
```
