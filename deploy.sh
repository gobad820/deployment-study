#!/bin/bash

# 1. 실행 중인 프로세스 종료
echo "> 현재 구동 중인 애플리케이션 pid 확인"
CURRENT_PID=$(pgrep -f .jar)

if [ -z "$CURRENT_PID" ]; then
    echo "> 현재 구동 중인 애플리케이션이 없으므로 종료하지 않습니다."
else
    echo "> kill -15 $CURRENT_PID"
    kill -15 $CURRENT_PID
    sleep 5
fi

# 2. 새 애플리케이션 배포
echo "> 새 애플리케이션 배포"
# jar 파일이 모이는 곳을 /home/ubuntu/app 으로 통일합니다.
JAR_PATH=$(ls -tr /home/ubuntu/app/*.jar | tail -n 1)

echo "> JAR Name: $JAR_PATH"

echo "> $JAR_PATH 에 실행권한 추가"
chmod +x $JAR_PATH

echo "> $JAR_PATH 실행"
# t2.micro 메모리 부족 방지 옵션 추가
nohup java -Xms256m -Xmx512m -jar $JAR_PATH > /home/ubuntu/app/app.log 2>&1 &