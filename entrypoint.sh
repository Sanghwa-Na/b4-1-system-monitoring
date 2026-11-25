#!/bin/bash
# ============================================================
# entrypoint.sh - 컨테이너 시작 스크립트
# ============================================================

set -e

echo "=========================================="
echo "B4-1 Mission Container Starting..."
echo "=========================================="

# SSH 서비스 시작
echo "[INFO] Starting SSH service on port [SSH_PORT]..."
service ssh start

# Cron 서비스 시작
echo "[INFO] Starting Cron service..."
service cron start

# UFW 방화벽 설정 (런타임에서 수행 - 커널 모듈 필요)
echo "[INFO] Configuring UFW firewall..."
ufw --force enable
ufw allow [SSH_PORT]/tcp
ufw allow [APP_PORT]/tcp
ufw default deny incoming
ufw default allow outgoing
echo "[INFO] UFW firewall configured"

# 환경 변수 설정 ([USER_ADMIN]용)
export AGENT_HOME=[AGENT_HOME]
export AGENT_PORT=[APP_PORT]
export AGENT_UPLOAD_DIR=[AGENT_HOME]/upload_files
export AGENT_KEY_PATH=[AGENT_HOME]/api_keys
export AGENT_LOG_DIR=[LOG_DIR]

# agent-app 실행 ([USER_ADMIN] 권한으로 백그라운드 실행)
echo "[INFO] Starting agent_app.py as [USER_ADMIN]..."
cd [AGENT_HOME]
sudo -u [USER_ADMIN] bash -c "
    export AGENT_HOME=[AGENT_HOME]
    export AGENT_PORT=[APP_PORT]
    export AGENT_UPLOAD_DIR=[AGENT_HOME]/upload_files
    export AGENT_KEY_PATH=[AGENT_HOME]/api_keys
    export AGENT_LOG_DIR=[LOG_DIR]
    exec ./agent_app.py
" &

APP_PID=$!
echo "[INFO] agent_app.py started with PID: ${APP_PID}"

# 앱 시작 대기
echo "[INFO] Waiting for agent app to initialize..."
sleep 5

# 앱 실행 확인
echo "[INFO] Verifying agent app status..."
if ss -tuln | grep -q ":[APP_PORT] "; then
    echo "[SUCCESS] Agent app is listening on port [APP_PORT]"
else
    echo "[WARNING] Agent app may not be listening on port [APP_PORT] yet"
fi

# 프로세스 확인
if pgrep -f "agent_app.py" >/dev/null; then
    echo "[SUCCESS] Agent app process is running"
else
    echo "[WARNING] Agent app process not found"
fi

echo "=========================================="
echo "Container is ready!"
echo "=========================================="
echo ""
echo "Access methods:"
echo "  SSH: ssh -p [SSH_PORT] [USER_ADMIN]@localhost"
echo "  Password: [PASSWORD]"
echo ""
echo "Verification commands:"
echo "  id [USER_ADMIN]"
echo "  id [USER_DEV]"
echo "  id [USER_TEST]"
echo "  ufw status"
echo "  ss -tulnp | grep -E '[SSH_PORT]|[APP_PORT]'"
echo "  ls -la [AGENT_HOME]/"
echo "  getfacl [AGENT_HOME]/upload_files"
echo "  getfacl [AGENT_HOME]/api_keys"
echo "  cat [LOG_DIR]/monitor.log"
echo "  crontab -u [USER_ADMIN] -l"
echo "=========================================="

# 컨테이너 유지
tail -f /dev/null