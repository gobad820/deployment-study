# deploy.sh 스크립트 가이드

## 위치

이 파일은 EC2 서버의 `/home/ubuntu/deploy.sh`에 직접 생성해야 한다.
GitHub 저장소에는 포함하지 않는 경우가 많다 (서버 설정 파일이므로).

## 전체 스크립트

```bash
#!/bin/bash

# ==========================================
# Blue-Green 무중단 배포 스크립트
# ==========================================

APP_DIR=/home/ubuntu/app
LOG_DIR=/home/ubuntu/app
NGINX_CONF=/etc/nginx/conf.d/service-url.inc

# 가장 최신 jar 파일 선택
JAR_NAME=$(ls -t $APP_DIR/*.jar | head -1)
echo "=== 배포할 JAR: $JAR_NAME ==="

# ------------------------------------------
# Step 1. 현재 실행 중인 프로파일 확인
# ------------------------------------------
echo "=== Step 1. 현재 프로파일 확인 ==="
CURRENT_PROFILE=$(curl -s http://localhost/profile)
echo "현재 실행 중인 프로파일: $CURRENT_PROFILE"

# 현재가 real1이면 → 유휴 대상은 real2 (8082)
# 현재가 real2이면 → 유휴 대상은 real1 (8081)
# 처음 배포(아무것도 안 뜬 경우) → real1로 시작
if [ "$CURRENT_PROFILE" == "real1" ]; then
    IDLE_PROFILE="real2"
    IDLE_PORT=8082
else
    IDLE_PROFILE="real1"
    IDLE_PORT=8081
fi

echo "신규 배포 대상: $IDLE_PROFILE (port: $IDLE_PORT)"

# ------------------------------------------
# Step 2. 유휴 포트에 실행 중인 기존 프로세스 종료
# ------------------------------------------
echo "=== Step 2. 포트 $IDLE_PORT 기존 프로세스 정리 ==="
IDLE_PID=$(lsof -ti tcp:$IDLE_PORT)

if [ -n "$IDLE_PID" ]; then
    echo "기존 프로세스 종료 (PID: $IDLE_PID)"
    kill -15 $IDLE_PID   # SIGTERM: Graceful Shutdown
    sleep 5
else
    echo "포트 $IDLE_PORT 에 실행 중인 프로세스 없음"
fi

# ------------------------------------------
# Step 3. 새 버전 앱 실행
# ------------------------------------------
echo "=== Step 3. 새 앱 실행: $IDLE_PROFILE ==="
nohup java -jar \
    -Dspring.profiles.active=$IDLE_PROFILE \
    $JAR_NAME \
    > $LOG_DIR/app-$IDLE_PROFILE.log 2>&1 &

echo "새 앱 PID: $!"

# ------------------------------------------
# Step 4. Health Check (최대 100초 대기)
# ------------------------------------------
echo "=== Step 4. Health Check 시작 ==="
MAX_RETRY=10
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRY ]; do
    sleep 10
    RETRY_COUNT=$((RETRY_COUNT + 1))

    # HTTP 상태 코드 확인
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$IDLE_PORT/profile)

    if [ "$HTTP_CODE" == "200" ]; then
        echo "✅ Health Check 성공! ($RETRY_COUNT/$MAX_RETRY)"
        break
    fi

    echo "⏳ 대기 중... ($RETRY_COUNT/$MAX_RETRY, HTTP: $HTTP_CODE)"

    if [ $RETRY_COUNT -eq $MAX_RETRY ]; then
        echo "❌ Health Check 실패. 배포를 중단합니다."
        exit 1
    fi
done

# ------------------------------------------
# Step 5. Nginx 트래픽 전환
# ------------------------------------------
echo "=== Step 5. Nginx 트래픽 전환 → $IDLE_PROFILE (port: $IDLE_PORT) ==="
echo "set \$service_url http://127.0.0.1:${IDLE_PORT};" | sudo tee $NGINX_CONF
sudo nginx -s reload

echo "✅ Nginx reload 완료"

# ------------------------------------------
# Step 6. 기존(구버전) 앱 종료
# ------------------------------------------
sleep 10   # 기존 요청이 처리 완료될 시간 확보

if [ -n "$CURRENT_PROFILE" ] && [ "$CURRENT_PROFILE" != "$IDLE_PROFILE" ]; then
    if [ "$CURRENT_PROFILE" == "real1" ]; then
        OLD_PORT=8081
    else
        OLD_PORT=8082
    fi

    OLD_PID=$(lsof -ti tcp:$OLD_PORT)

    if [ -n "$OLD_PID" ]; then
        echo "=== Step 6. 기존 앱 종료: $CURRENT_PROFILE (PID: $OLD_PID) ==="
        kill -15 $OLD_PID   # SIGTERM
        echo "✅ 기존 앱 종료 완료"
    fi
else
    echo "=== Step 6. 최초 배포이므로 종료할 기존 앱 없음 ==="
fi

echo ""
echo "🎉 Blue-Green 배포 완료!"
echo "   현재 운영: $IDLE_PROFILE (port: $IDLE_PORT)"
```

## EC2에 파일 생성 방법

```bash
# EC2 SSH 접속 후
vi /home/ubuntu/deploy.sh
# 위 스크립트 내용 붙여넣기

# 실행 권한 부여
chmod +x /home/ubuntu/deploy.sh
```

## 각 단계 상세 설명

### Step 1 - 현재 프로파일 확인

```bash
CURRENT_PROFILE=$(curl -s http://localhost/profile)
```

- Nginx를 통해 `/profile` 엔드포인트를 호출
- `localhost`(80번)로 호출하면 Nginx가 현재 트래픽을 보내는 쪽의 응답을 받음
- 응답값: `real1` 또는 `real2`
- **최초 배포 시**: 아무것도 실행 중이 아니면 curl이 빈 문자열 반환 → `else` 분기로 `real1`부터 시작

### Step 2 - 유휴 포트 정리

이전 배포에서 정상 종료되지 않은 프로세스가 있을 경우를 대비한 정리 단계.

### Step 3 - 새 앱 실행

```bash
nohup java -jar -Dspring.profiles.active=$IDLE_PROFILE $JAR_NAME > ... &
```

- `nohup`: SSH 세션이 끊겨도 프로세스 유지
- `-Dspring.profiles.active`: JVM 시스템 프로퍼티로 프로파일 지정
- `&`: 백그라운드 실행 (deploy.sh가 블로킹되지 않음)

### Step 4 - Health Check

새 앱이 완전히 뜨기까지 시간이 걸린다.
10초마다 한 번씩, 최대 10번(100초) 시도한다.
HTTP 200이 오면 성공으로 판단.

### Step 5 - Nginx 전환

파일 한 줄을 교체하고 `nginx -s reload`.
이 순간부터 모든 새 요청은 신버전으로 간다.

### Step 6 - 기존 앱 종료

`kill -15` (SIGTERM) 을 사용한다.
- **SIGTERM**: "이제 종료해" 신호 → Spring Boot는 현재 처리 중인 요청을 마친 후 종료 (Graceful Shutdown)
- **SIGKILL (-9)**: 즉시 강제 종료 → 처리 중인 요청이 끊길 수 있으므로 지양

> Spring Boot 2.3+ 에서 `server.shutdown=graceful` 설정 시 SIGTERM을 받으면 새 요청은 거부하고 기존 요청 처리 후 종료한다.

## 기존 앱은 종료해야 하는가?

> **결론: 종료한다. 단, Nginx 전환 이후에, 기존 요청이 완료될 시간을 주고 나서 종료한다.**

### 종료하는 이유

1. **자원 효율**: 두 인스턴스를 계속 유지하면 메모리, CPU 낭비
2. **다음 배포를 위해**: 다음 번 배포 때 유휴 포트가 비어있어야 함
3. **포트 충돌 방지**: 같은 포트에 두 프로세스가 뜰 수 없음

### 종료 타이밍

```
Nginx 전환 완료
    │
    ├── [10초 대기] ← 기존 연결(Keep-Alive, 처리 중인 요청) 소진 대기
    │
    └── kill -15 (SIGTERM)
```

실무에서는 이 대기 시간을 길게 가져가거나, 로드밸런서의 드레이닝(Draining) 기능을 활용한다.
