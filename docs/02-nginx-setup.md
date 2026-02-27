# Nginx 설정 가이드

## Nginx 역할

Blue-Green 배포에서 Nginx는 **트래픽 스위치** 역할을 한다.
- 외부(80번 포트) 요청을 받아 내부(8081 or 8082)로 전달
- `deploy.sh`에서 설정 파일 한 줄만 바꾸고 `nginx -s reload`하면 트래픽이 즉시 전환됨
- reload는 **무중단** (기존 커넥션을 유지하면서 설정만 교체)

## EC2에 Nginx 설치

```bash
sudo apt update
sudo apt install -y nginx
sudo systemctl enable nginx
sudo systemctl start nginx
```

## 설정 파일 구성

### 1. 동적 포트 파일 생성

`/etc/nginx/conf.d/service-url.inc` 파일을 생성한다.
이 파일 한 줄만 바꿔서 트래픽을 전환한다.

```bash
# 초기값: real1(8081)로 설정
echo "set \$service_url http://127.0.0.1:8081;" | sudo tee /etc/nginx/conf.d/service-url.inc
```

파일 내용:
```nginx
set $service_url http://127.0.0.1:8081;
```

### 2. Nginx 서버 블록 설정

`/etc/nginx/sites-available/default` 파일을 아래와 같이 수정한다.

```bash
sudo vi /etc/nginx/sites-available/default
```

```nginx
server {
    listen 80;
    server_name _;   # 모든 도메인 허용 (도메인이 있으면 도메인명으로 변경)

    include /etc/nginx/conf.d/service-url.inc;  # 동적 포트 파일 include

    location / {
        proxy_pass $service_url;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### 3. 설정 검증 및 적용

```bash
# 설정 문법 검사
sudo nginx -t

# Nginx 재시작 (처음 설정 시)
sudo systemctl restart nginx

# 설정 리로드 (무중단, 이후 배포 시)
sudo nginx -s reload
```

## 트래픽 전환 원리

`deploy.sh`에서 아래 명령 한 줄로 전환이 이루어진다.

```bash
# 8081 → 8082로 전환하는 경우
echo "set \$service_url http://127.0.0.1:8082;" | sudo tee /etc/nginx/conf.d/service-url.inc
sudo nginx -s reload
```

`nginx -s reload`는:
- 기존에 처리 중이던 요청은 구 워커 프로세스가 끝까지 처리
- 새 요청부터는 새 설정(새 포트)으로 전달
- **다운타임 0**

## sudo 권한 설정 (deploy.sh에서 sudo 없이 실행하려면)

GitHub Actions에서 SSH로 실행하는 ubuntu 계정이 sudo 없이 nginx 명령을 쓸 수 있도록 설정한다.

```bash
# EC2에서 실행
sudo visudo
```

아래 줄 추가:
```
ubuntu ALL=(ALL) NOPASSWD: /usr/sbin/nginx, /bin/tee /etc/nginx/conf.d/service-url.inc
```

## Healthcheck와 Spring Actuator

### Spring Actuator란?

Spring Boot에서 제공하는 **애플리케이션 상태 모니터링 라이브러리**.
`/actuator/health` 엔드포인트를 통해 앱이 정상인지 확인할 수 있다.

```json
// GET /actuator/health 응답 예시
{
    "status": "UP"
}
```

### 업계에서의 사용 여부

Actuator의 `/actuator/health`는 Spring 생태계에서 **사실상 표준(de facto standard)** 이다.
- Kubernetes의 liveness/readiness probe에서도 이 엔드포인트를 사용
- DB 연결, 디스크, 메모리 상태 등 다양한 지표를 한 번에 확인 가능

### 지금 단계에서 꼭 필요한가?

> **결론: 학습 단계에서는 현재 `/profile` 엔드포인트로 충분하다.**

| | `/profile` 엔드포인트 | `/actuator/health` |
|---|---|---|
| 학습 단계 | 충분함 | 과잉 |
| 실무 | 기능 제한적 | 권장 |
| DB/외부 서비스 연결 확인 | 불가 | 가능 |

나중에 DB나 Redis 등 외부 의존성이 생기면 그때 Actuator를 도입하면 된다.
지금은 `curl -s http://localhost:$IDLE_PORT/profile`로 응답이 오면 정상으로 판단해도 된다.
