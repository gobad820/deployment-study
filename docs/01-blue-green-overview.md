# Blue-Green 무중단 배포 개요

## 무중단 배포란?

서비스를 재시작할 때 **사용자 요청이 끊기는 순간(다운타임)이 없도록** 배포하는 방식.
일반적인 배포는 기존 서버를 내리고 새 버전을 올리는 과정에서 짧게라도 요청이 실패한다.
무중단 배포는 이 구간을 없앤다.

## Blue-Green 배포 방식

두 개의 동일한 환경을 유지한다.

```
[사용자]
    │
    ▼
[Nginx: 80번 포트] ← 트래픽을 전환하는 스위치 역할
    │
    ├─── [Blue: 8081] ← 현재 운영 중
    │
    └─── [Green: 8082] ← 대기 중 (다음 배포 대상)
```

### 배포 순서

1. 현재 **Blue (8081)** 가 트래픽 처리 중
2. 새 버전 JAR를 **Green (8082)** 에 배포 & 실행
3. Green이 정상 동작하는지 **헬스체크** 확인
4. Nginx가 트래픽을 **8082로 전환** (사용자는 아무것도 모름)
5. Blue (8081) 프로세스 **종료**
6. 다음 배포 시: Green → Blue 순서로 반복

### 이 프로젝트의 구성

| 환경 | Spring Profile | 포트 |
|------|---------------|------|
| Blue | `real1` | 8081 |
| Green | `real2` | 8082 |

- `ProfileController`의 `/profile` 엔드포인트 → 현재 어떤 인스턴스가 활성인지 확인
- `application-real1.properties` → `server.port=8081`
- `application-real2.properties` → `server.port=8082`

## 다른 무중단 배포 방식과 비교

| 방식 | 설명 | 장점 | 단점 |
|------|------|------|------|
| **Blue-Green** | 동일 서버 2개 전환 | 빠른 롤백, 단순함 | 서버 2배 필요 |
| **Rolling** | 인스턴스를 순차적으로 교체 | 자원 효율적 | 배포 중 구버전/신버전 공존 |
| **Canary** | 일부 트래픽만 신버전으로 | 위험 최소화 | 복잡한 설정 |

학습 단계에서는 **Blue-Green이 가장 직관적이고 구현이 단순**해서 먼저 익히기 좋다.

## 전체 시스템 구성도

```
GitHub Push
    │
    ▼
GitHub Actions
    ├── Gradle Build → *.jar 생성
    ├── SCP → EC2 /home/ubuntu/app/ 에 전송
    └── SSH → deploy.sh 실행
                    │
                    ▼
                EC2 서버
                ├── Nginx (80) ← 외부 트래픽 수신
                ├── real1 (8081) ← Spring Boot
                └── real2 (8082) ← Spring Boot
```
