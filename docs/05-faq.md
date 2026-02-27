# FAQ: 자주 묻는 질문

## Q1. SCP로 JAR 파일을 옮기면 이미 돌아가는 서버의 JAR 파일이 바뀌어버리는데, 이게 가능한가? 서버 운영에 문제는 없나?

### 결론: 가능하다. 실행 중인 서버에는 영향이 없다.

### 이유

Java JVM이 JAR 파일을 실행하는 방식을 이해하면 된다.

```
JAR 파일 실행 시:
java -jar app.jar
    │
    ▼
JVM이 JAR 파일을 열고 클래스 파일을 메모리에 로드
    │
    ▼
이후 JVM은 메모리에 올라간 코드를 실행
(디스크의 JAR 파일을 계속 참조하지 않음)
```

즉, **JAR 파일이 디스크에서 변경되어도 이미 실행 중인 JVM 프로세스는 전혀 영향을 받지 않는다.**
메모리에 올라간 코드를 실행하는 것이기 때문.

### SCP 전송과 deploy.sh 실행 순서

```
GitHub Actions 워크플로우 실행 순서:
1. SCP로 JAR 전송 완료 ← 이 step이 끝난 후에
2. SSH로 deploy.sh 실행 ← 다음 step 실행
```

SCP 전송 중(파일이 불완전한 상태)에는 deploy.sh가 실행되지 않으므로 안전하다.

### 실제로 문제가 생기는 경우

Blue (real1, 8081)가 실행 중에 `/home/ubuntu/app/app.jar` 파일이 교체됨
→ Blue 프로세스에는 영향 없음 (메모리의 코드 실행 중)
→ deploy.sh에서 Green (real2, 8082)을 새 JAR로 실행할 때 새 버전이 뜸
→ 정상 동작

---

## Q2. 포트 변경만 하는 경우에도 Spring Profile을 쓰는 게 좋은가? Profile이 업계 표준(de facto)인가?

### 결론: 포트만 다를 때도 Profile 사용이 좋다. Spring 생태계에서는 사실상 표준이다.

### Profile을 쓰는 이유

**명시성**: `real1`이 실행 중인지 `real2`가 실행 중인지 코드 레벨에서 명확하게 표현됨
```java
// ProfileController에서 현재 인스턴스를 구분할 수 있음
List<String> profiles = Arrays.asList(env.getActiveProfiles()); // ["real1"] 또는 ["real2"]
```

**확장성**: 지금은 포트만 다르지만, 나중에 환경별로 다른 설정이 생길 때 자연스럽게 확장 가능
```properties
# application-real1.properties
server.port=8081
# 나중에 필요하면 추가
spring.datasource.url=jdbc:...
logging.level.root=INFO
```

**Spring 생태계 관행**: Spring 공식 문서, 유명 기술 블로그, 실무 모두 Profile을 기본으로 사용

### 대안과 비교

| 방법 | 예시 | 특징 |
|------|------|------|
| **Spring Profile** | `-Dspring.profiles.active=real1` | Spring 표준, 권장 |
| 환경변수 | `SERVER_PORT=8081` | OS 레벨, Spring 무관 |
| 커맨드라인 인자 | `--server.port=8081` | 단순하지만 확장성 제한 |

Profile이 de facto standard인 이유: 설정 분리, 조건부 Bean 생성, 테스트 환경 구분 등 다양한 상황에 활용 가능하고 Spring이 공식 지원하는 기능이기 때문.

---

## Q3. Nginx healthcheck에 Spring Actuator를 쓰던데, 업계 표준인가? 지금 공부 단계에서 꼭 써야 하는가?

### 결론: Actuator는 업계 표준이지만, 지금 단계에서는 `/profile` 엔드포인트로 충분하다.

### Spring Actuator란?

`spring-boot-starter-actuator` 의존성을 추가하면 자동으로 `/actuator/health` 엔드포인트가 열린다.

```json
// GET /actuator/health 응답
{
    "status": "UP",
    "components": {
        "db": { "status": "UP" },
        "diskSpace": { "status": "UP" },
        "ping": { "status": "UP" }
    }
}
```

### 업계에서의 위상

- Kubernetes liveness/readiness probe에서 표준으로 사용
- AWS ELB(로드밸런서) 헬스체크 타겟으로 자주 사용
- Spring 기반 MSA에서 거의 필수적으로 채택

### 언제 도입해야 하는가?

| 상황 | 권장 |
|------|------|
| 현재 (포트만 다른 간단한 앱) | `/profile` 엔드포인트로 충분 |
| DB, Redis 등 외부 의존성 있음 | Actuator 도입 권장 |
| Kubernetes 환경 | Actuator 필수에 가까움 |
| 실무 프로덕션 | Actuator 사용이 표준 |

현재 이 프로젝트는 이미 `build.gradle`에 Actuator 의존성이 있다:
```groovy
implementation 'org.springframework.boot:spring-boot-starter-actuator'
```

따라서 `http://localhost:$IDLE_PORT/actuator/health`도 지금 당장 사용 가능하다.
학습 목적에서는 `/profile`도 역할이 동일하므로 어느 것을 써도 무방하다.

---

## Q4. Blue-Green 배포에서 업데이트가 완료되면 기존 서버를 그냥 닫아버리는가?

### 결론: 닫는다. 단, 즉시 kill이 아니라 처리 중인 요청이 끝날 시간을 준 후에 종료한다.

### 전체 흐름

```
[기존: Blue(8081) 운영 중]
        │
        ▼
Green(8082)에 새 버전 배포 & 실행
        │
        ▼
Health Check 통과
        │
        ▼
Nginx: 8081 → 8082로 트래픽 전환 (이 순간부터 새 요청은 모두 Green으로)
        │
        ▼
[약 10초 대기] ← Blue에 들어온 기존 요청 처리 완료 대기
        │
        ▼
Blue(8081) 프로세스 종료 (kill -15, SIGTERM)
```

### kill -15 vs kill -9

```bash
kill -15 $OLD_PID   # SIGTERM: "정상 종료해줘" 요청
kill -9 $OLD_PID    # SIGKILL: 즉시 강제 종료
```

**SIGTERM (-15)**: Spring Boot가 시그널을 받아 현재 처리 중인 요청을 마친 후 정상 종료
**SIGKILL (-9)**: OS가 즉시 프로세스를 죽임. 처리 중인 요청이 강제로 끊김

무중단 배포의 목적을 살리려면 **반드시 SIGTERM을 사용**해야 한다.

### Spring Boot Graceful Shutdown 설정 (선택사항)

`application.properties`에 추가하면 SIGTERM 수신 시 새 요청을 거부하고 기존 요청 완료 후 종료:

```properties
server.shutdown=graceful
spring.lifecycle.timeout-per-shutdown-phase=30s  # 최대 30초 대기
```

### 기존 서버를 유지하는 전략도 있는가?

실무에서는 롤백을 위해 기존 서버를 잠시 유지하는 경우도 있다.

```
Nginx 전환 완료
    │
    ├── [모니터링 기간 유지] ← 이 기간에 에러율, 응답시간 확인
    │        문제 없으면 → Blue 종료
    │        문제 있으면 → Nginx를 다시 Blue로 전환 (롤백)
    └── Blue 종료
```

현재 학습 단계에서는 단순하게 **전환 후 즉시 종료**하는 방식으로 구현해도 충분하다.
