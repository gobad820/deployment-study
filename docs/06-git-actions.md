아래는 요청하신 내용을 **Markdown(.md) 파일 형식**으로 구조화·정리한 버전입니다.
그대로 `README.md` 또는 문서 파일로 사용하셔도 됩니다.

---

# 왜 Gradle을 설치하지 않아도 되는가?

## 핵심: `gradlew`는 이미 저장소에 있다

`actions/checkout@v4` 가 실행되면 저장소의 모든 파일이 Runner에 복사된다.
여기에 `gradlew` 스크립트도 포함된다.

### Checkout 후 Runner 파일 구조

```
├── gradlew          ← 이미 존재 (저장소에 커밋됨)
├── gradlew.bat
├── gradle/
│   └── wrapper/
│       ├── gradle-wrapper.jar
│       └── gradle-wrapper.properties  ← Gradle 버전 명시
└── ...
```

---

## gradlew의 동작 원리

`gradlew`는 **Gradle Wrapper 스크립트**이며, 내부적으로 다음과 같이 동작한다.

```
./gradlew 실행
    │
    ▼
gradle-wrapper.properties 읽음
    └── distributionUrl=https://services.gradle.org/distributions/gradle-9.3.0-bin.zip
    │
    ▼
~/.gradle/wrapper/dists/ 에 Gradle 9.3.0이 있는가?
    │
    ├── 없으면 → URL에서 다운로드 후 저장
    └── 있으면 → 그냥 사용 (캐시 히트)
```

### 결론

> Gradle 설치는 `./gradlew`를 처음 실행할 때 자동으로 일어난다.
> 따라서 CI에서 별도로 Gradle을 설치할 필요가 없다.

---

# 그럼 캐싱은 무슨 역할인가?

```yaml
- name: Gradle Caching
  uses: actions/cache@v3
  with:
    path: |
      ~/.gradle/caches    # ← 의존성(라이브러리) 캐시
      ~/.gradle/wrapper   # ← Gradle 배포판 자체 캐시
    key: ${{ runner.os }}-gradle-${{ hashFiles('**/*.gradle*', '**/gradle-wrapper.properties') }}
```

## 왜 캐싱이 필요한가?

GitHub Actions의 Runner는 **매 실행마다 새로운 깨끗한 VM**이다.
이전 실행에서 다운로드한 파일들은 모두 사라진다.

---

## ❌ 캐싱이 없으면

매 push마다:

* Gradle 9.3.0 다운로드 (수십 MB)
* Spring Boot 의존성 전체 다운로드 (수백 MB)

→ 매번 몇 분씩 소요

---

## ✅ 캐싱이 있으면

### 첫 번째 push

* Gradle + 의존성 다운로드
* `~/.gradle/` 에 저장
* 워크플로우 종료 시 GitHub Cache에 업로드

### 두 번째 push부터

* GitHub Cache에서 `~/.gradle/` 복원 (restore)
* `./gradlew` 실행 시 이미 존재 → 다운로드 스킵

---

# 워크플로우 전체 흐름 (단계별 정리)

---

## Step 1. Checkout

```yaml
- uses: actions/checkout@v4
```

**역할**

* 저장소 파일 전체를 Runner VM에 복사
* `gradlew`, `build.gradle`, 소스코드 포함

---

## Step 2. JDK 설치

```yaml
- name: Set up JDK 21
  uses: actions/setup-java@v4
  with:
    distribution: 'temurin'
    java-version: '21'
```

**왜 필요한가?**

* Gradle은 Java 위에서 동작
* 프로젝트도 Java 기반
* Runner에 JDK가 기본 설치되어 있지 않거나 버전이 맞지 않을 수 있음

→ 반드시 명시적으로 설치

---

## Step 3. Gradle 캐싱

```yaml
- name: Gradle Caching
  uses: actions/cache@v3
  with:
    path: |
      ~/.gradle/caches
      ~/.gradle/wrapper
    key: ${{ runner.os }}-gradle-${{ hashFiles('**/*.gradle*', '**/gradle-wrapper.properties') }}
    restore-keys: |
      ${{ runner.os }}-gradle-
```

### key 설명

```yaml
${{ hashFiles('**/*.gradle*', '**/gradle-wrapper.properties') }}
```

* `build.gradle` 변경 시
* 의존성 추가/삭제 시
* Gradle 버전 변경 시

→ 새로운 캐시 생성

---

### restore-keys 설명

정확한 key가 매칭되지 않으면 prefix 기반 fallback 수행.

```yaml
${{ runner.os }}-gradle-
```

의존성이 일부만 바뀐 경우 기존 캐시를 최대한 활용하기 위한 전략.

---

## Step 4. 실행 권한 부여

```yaml
- name: Grant execute permission for gradlew
  run: chmod +x gradlew
```

### 왜 필요한가?

* Linux에서 스크립트 실행에는 `+x` 권한 필요
* Git은 실행 권한을 추적하긴 하지만
* Windows 환경 등에서는 체크아웃 시 권한이 초기화될 수 있음

→ CI에서는 명시적으로 추가하는 것이 관행

---

## Step 5. Gradle 빌드

```yaml
- name: Build with Gradle
  run: ./gradlew clean build -x test
```

### 수행 내용

* Gradle 9.3.0 사용 (캐시 or 다운로드)
* 프로젝트 빌드
* `build/libs/` 아래에 JAR 생성

---

## Step 6. EC2로 JAR 전송

```yaml
- name: Transfer Jar to EC2
  uses: appleboy/scp-action@master
  with:
    source: "./build/libs/*.jar"
    target: "/home/ubuntu/app"
    strip_components: 2
```

### 설명

* 빌드된 JAR를 SCP로 EC2에 전송
* `strip_components: 2`
  → `build/libs/` 경로 제거 후 파일만 전송

---

## Step 7. 배포 실행

```yaml
- name: Deploy
  uses: appleboy/ssh-action@v1.0.3
  with:
    script: |
      chmod +x /home/ubuntu/deploy.sh
      /home/ubuntu/deploy.sh
```

### 수행 내용

* EC2에 SSH 접속
* `deploy.sh` 실행
* Blue-Green 배포 전환 수행

---

# 한 줄 정리

| 역할           | 담당                                |
| ------------ | --------------------------------- |
| Gradle 스크립트  | `gradlew` (저장소에 커밋)               |
| Gradle 버전 명시 | `gradle-wrapper.properties`       |
| Gradle 실제 설치 | `./gradlew` 첫 실행 시 자동             |
| 재다운로드 방지     | `actions/cache` 로 `~/.gradle/` 캐싱 |
| JDK 설치       | `actions/setup-java` (명시적 설치 필요)  |

---

# 최종 핵심 요약

> ✅ Gradle은 설치하지 않는다.
> ✅ `gradlew`가 자동으로 설치한다.
> ✅ 캐시는 다운로드 시간을 줄이기 위한 최적화 장치다.
> ✅ JDK만 명시적으로 설치하면 된다.
