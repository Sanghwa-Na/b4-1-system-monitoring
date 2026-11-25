# B4-1 Mission Solution - AI 도구 학습
# Ubuntu 22.04 기반 Docker 이미지
#
# 빌드: docker build -t [IMAGE_NAME] .
# 실행: docker run -d -p [SSH_PORT]:[SSH_PORT] -p [APP_PORT]:[APP_PORT] --name [CONTAINER_NAME] [IMAGE_NAME]
# 접속: ssh -p [SSH_PORT] [USER_ADMIN]@localhost

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# 필수 패키지 설치
RUN apt-get update && apt-get install -y \
    openssh-server \
    ufw \
    sudo \
    cron \
    logrotate \
    procps \
    net-tools \
    iproute2 \
    curl \
    vim \
    acl \
    bc \
    && rm -rf /var/lib/apt/lists/*

# SSH 설정: 포트 [SSH_PORT], Root 로그인 차단
RUN mkdir -p /var/run/sshd
RUN sed -i 's/^#Port 22/Port [SSH_PORT]/' /etc/ssh/sshd_config
RUN sed -i 's/^Port 22/Port [SSH_PORT]/' /etc/ssh/sshd_config
RUN sed -i 's/^#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
RUN sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
# PasswordAuthentication 활성화 (테스트용)
RUN sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
RUN sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config

# 사용자 및 그룹 생성
# [GROUP_COMMON]: admin, dev, test 모두 포함 (공유 디렉토리용)
# [GROUP_CORE]: admin, dev만 포함 (보안 디렉토리용, cron 실행자)
RUN groupadd -f [GROUP_COMMON]
RUN groupadd -f [GROUP_CORE]
RUN useradd -m -s /bin/bash -G [GROUP_COMMON],[GROUP_CORE] [USER_ADMIN]
RUN useradd -m -s /bin/bash -G [GROUP_COMMON],[GROUP_CORE] [USER_DEV]
RUN useradd -m -s /bin/bash -G [GROUP_COMMON] [USER_TEST]

# 비밀번호 설정 (sudo용)
RUN echo '[USER_ADMIN]:[PASSWORD]' | chpasswd
RUN echo '[USER_DEV]:[PASSWORD]' | chpasswd
RUN echo '[USER_TEST]:[PASSWORD]' | chpasswd
RUN echo 'root:root' | chpasswd

# sudo 권한 부여 (필요한 경우만)
RUN echo '[USER_ADMIN] ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
RUN echo '[USER_DEV] ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# 디렉토리 구조 생성 (AGENT_HOME 기준)
# AGENT_HOME = [AGENT_HOME]
RUN mkdir -p [AGENT_HOME]/bin
RUN mkdir -p [AGENT_HOME]/upload_files
RUN mkdir -p [AGENT_HOME]/api_keys
RUN mkdir -p [LOG_DIR]
RUN mkdir -p [ARCHIVE_DIR]

# 권한 설정 (핵심 정책)
# upload_files: group=[GROUP_COMMON], R/W 가능 (모든 사용자 공유)
RUN chown [USER_ADMIN]:[GROUP_COMMON] [AGENT_HOME]/upload_files
RUN chmod 770 [AGENT_HOME]/upload_files
RUN setfacl -m g:[GROUP_COMMON]:rwx [AGENT_HOME]/upload_files
RUN setfacl -d -m g:[GROUP_COMMON]:rwx [AGENT_HOME]/upload_files

# api_keys: group=[GROUP_CORE] ONLY, R/W 가능 (admin, dev만 접근)
RUN chown [USER_ADMIN]:[GROUP_CORE] [AGENT_HOME]/api_keys
RUN chmod 770 [AGENT_HOME]/api_keys
RUN setfacl -m g:[GROUP_CORE]:rwx [AGENT_HOME]/api_keys
RUN setfacl -d -m g:[GROUP_CORE]:rwx [AGENT_HOME]/api_keys

# [LOG_DIR]: group=[GROUP_CORE] ONLY, R/W 가능
RUN chown [USER_ADMIN]:[GROUP_CORE] [LOG_DIR]
RUN chmod 770 [LOG_DIR]
RUN setfacl -m g:[GROUP_CORE]:rwx [LOG_DIR]
RUN setfacl -d -m g:[GROUP_CORE]:rwx [LOG_DIR]

# bin 디렉토리: owner=[USER_DEV], group=[GROUP_CORE], 권한 750
RUN chown [USER_DEV]:[GROUP_CORE] [AGENT_HOME]/bin
RUN chmod 750 [AGENT_HOME]/bin

# 아카이브 디렉토리
RUN chown [USER_ADMIN]:[GROUP_CORE] [ARCHIVE_DIR]
RUN chmod 770 [ARCHIVE_DIR]

# 애플리케이션 바이너리 복사
COPY agent-app-linux-x86 [AGENT_HOME]/agent_app.py
RUN chmod +x [AGENT_HOME]/agent_app.py
RUN chown [USER_ADMIN]:[GROUP_CORE] [AGENT_HOME]/agent_app.py

# 키 파일 생성 (앱이 secret.key 기대)
RUN echo '[API_KEY]' > [AGENT_HOME]/api_keys/secret.key
RUN chown [USER_ADMIN]:[GROUP_CORE] [AGENT_HOME]/api_keys/secret.key
RUN chmod 660 [AGENT_HOME]/api_keys/secret.key

# monitor.sh 스크립트 복사
COPY monitor.sh [AGENT_HOME]/bin/monitor.sh
RUN chown [USER_DEV]:[GROUP_CORE] [AGENT_HOME]/bin/monitor.sh
RUN chmod 750 [AGENT_HOME]/bin/monitor.sh

# logrotate 설정 복사
COPY logrotate-agent-app /etc/logrotate.d/agent-app

# verify.sh 복사 (검증용)
COPY verify.sh /verify.sh
RUN chmod +x /verify.sh

# cron 설정 ([USER_ADMIN] 계정으로 매분 실행)
RUN echo '* * * * * [AGENT_HOME]/bin/monitor.sh >> [LOG_DIR]/monitor-cron.log 2>&1' > /var/spool/cron/crontabs/[USER_ADMIN]
RUN chown [USER_ADMIN]:crontab /var/spool/cron/crontabs/[USER_ADMIN]
RUN chmod 600 /var/spool/cron/crontabs/[USER_ADMIN]

# UFW 방화벽 설정은 런타임(entrypoint.sh)에서 수행 (빌드 시 커널 모듈 미사용)

# 포트 노출
EXPOSE [SSH_PORT] [APP_PORT]

# 엔트리포인트 스크립트 복사
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]