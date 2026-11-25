#!/bin/bash
# ============================================================
# verify.sh - B4-1 미션 검증 스크립트
# ============================================================
# 모든 요구사항을 자동으로 검증합니다.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS=0
FAIL=0
WARN=0

check_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    PASS=$((PASS+1))
}

check_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    FAIL=$((FAIL+1))
}

check_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    WARN=$((WARN+1))
}

echo "=========================================="
echo "B4-1 Mission Verification"
echo "=========================================="
echo ""

# 1. SSH 설정 검증
echo "--- 1. SSH Configuration ---"
if grep -q "^Port [SSH_PORT]" /etc/ssh/sshd_config; then
    check_pass "SSH port is [SSH_PORT]"
else
    check_fail "SSH port is not [SSH_PORT]"
fi

if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then
    check_pass "Root login is disabled"
else
    check_fail "Root login is not disabled"
fi

if ss -tuln | grep -q ":[SSH_PORT] "; then
    check_pass "SSH is listening on port [SSH_PORT]"
else
    check_fail "SSH is not listening on port [SSH_PORT]"
fi

# 2. 방화벽 검증
echo ""
echo "--- 2. Firewall Configuration ---"
if sudo ufw status | grep -q "Status: active"; then
    check_pass "UFW is active"
else
    check_fail "UFW is not active"
fi

if sudo ufw status | grep -q "[SSH_PORT]/tcp"; then
    check_pass "Port [SSH_PORT]/tcp is allowed"
else
    check_fail "Port [SSH_PORT]/tcp is not allowed"
fi

if sudo ufw status | grep -q "[APP_PORT]/tcp"; then
    check_pass "Port [APP_PORT]/tcp is allowed"
else
    check_fail "Port [APP_PORT]/tcp is not allowed"
fi

# 3. 계정/그룹 검증
echo ""
echo "--- 3. Users and Groups ---"
for user in [USER_ADMIN] [USER_DEV] [USER_TEST]; do
    if id "$user" &>/dev/null; then
        check_pass "User $user exists"
    else
        check_fail "User $user does not exist"
    fi
done

for group in [GROUP_COMMON] [GROUP_CORE]; do
    if getent group "$group" &>/dev/null; then
        check_pass "Group $group exists"
    else
        check_fail "Group $group does not exist"
    fi
done

# 그룹 멤버십 확인
if id [USER_ADMIN] | grep -q "[GROUP_COMMON]" && id [USER_ADMIN] | grep -q "[GROUP_CORE]"; then
    check_pass "[USER_ADMIN] is in [GROUP_COMMON] and [GROUP_CORE]"
else
    check_fail "[USER_ADMIN] group membership incorrect"
fi

if id [USER_DEV] | grep -q "[GROUP_COMMON]" && id [USER_DEV] | grep -q "[GROUP_CORE]"; then
    check_pass "[USER_DEV] is in [GROUP_COMMON] and [GROUP_CORE]"
else
    check_fail "[USER_DEV] group membership incorrect"
fi

if id [USER_TEST] | grep -q "[GROUP_COMMON]" && ! id [USER_TEST] | grep -q "[GROUP_CORE]"; then
    check_pass "[USER_TEST] is in [GROUP_COMMON] only (not in [GROUP_CORE])"
else
    check_fail "[USER_TEST] group membership incorrect"
fi

# 4. 디렉토리 구조 및 권한 검증
echo ""
echo "--- 4. Directory Structure and Permissions ---"
AGENT_HOME="[AGENT_HOME]"

for dir in "$AGENT_HOME" "$AGENT_HOME/bin" "$AGENT_HOME/upload_files" "$AGENT_HOME/api_keys" "[LOG_DIR]" "[ARCHIVE_DIR]"; do
    if [[ -d "$dir" ]]; then
        check_pass "Directory exists: $dir"
    else
        check_fail "Directory missing: $dir"
    fi
done

# upload_files: group=[GROUP_COMMON], R/W
if stat -c "%G" "$AGENT_HOME/upload_files" | grep -q "[GROUP_COMMON]"; then
    check_pass "upload_files group is [GROUP_COMMON]"
else
    check_fail "upload_files group is not [GROUP_COMMON]"
fi

if [[ -w "$AGENT_HOME/upload_files" ]]; then
    check_pass "upload_files is writable"
else
    check_fail "upload_files is not writable"
fi

# api_keys: group=[GROUP_CORE] ONLY
if stat -c "%G" "$AGENT_HOME/api_keys" | grep -q "[GROUP_CORE]"; then
    check_pass "api_keys group is [GROUP_CORE]"
else
    check_fail "api_keys group is not [GROUP_CORE]"
fi

# [LOG_DIR]: group=[GROUP_CORE] ONLY
if stat -c "%G" "[LOG_DIR]" | grep -q "[GROUP_CORE]"; then
    check_pass "[LOG_DIR] group is [GROUP_CORE]"
else
    check_fail "[LOG_DIR] group is not [GROUP_CORE]"
fi

# bin 디렉토리: owner=[USER_DEV], group=[GROUP_CORE], 750
if stat -c "%U:%G" "$AGENT_HOME/bin" | grep -q "[USER_DEV]:[GROUP_CORE]"; then
    check_pass "bin owner:group is [USER_DEV]:[GROUP_CORE]"
else
    check_fail "bin owner:group is not [USER_DEV]:[GROUP_CORE]"
fi

if stat -c "%a" "$AGENT_HOME/bin" | grep -q "750"; then
    check_pass "bin permissions are 750"
else
    check_fail "bin permissions are not 750"
fi

# 5. 환경 변수 및 키 파일 검증
echo ""
echo "--- 5. Environment Variables and Key File ---"
if [[ -f "$AGENT_HOME/api_keys/secret.key" ]]; then
    check_pass "Key file exists"
    if grep -q "[API_KEY]" "$AGENT_HOME/api_keys/secret.key"; then
        check_pass "Key file content is correct"
    else
        check_fail "Key file content is incorrect"
    fi
else
    check_fail "Key file does not exist"
fi

# 6. 앱 실행 검증
echo ""
echo "--- 6. Application Boot Sequence ---"
if pgrep -f "agent_app.py" >/dev/null; then
    check_pass "agent_app.py process is running"

    # Boot sequence 확인 (로그에서)
    if ss -tuln | grep -q ":[APP_PORT] "; then
        check_pass "App is listening on port [APP_PORT]"
    else
        check_fail "App is not listening on port [APP_PORT]"
    fi
else
    check_fail "agent_app.py process is not running"
fi

# 7. monitor.sh 검증
echo ""
echo "--- 7. monitor.sh Script ---"
MONITOR_SCRIPT="$AGENT_HOME/bin/monitor.sh"
if [[ -f "$MONITOR_SCRIPT" ]]; then
    check_pass "monitor.sh exists"

    if stat -c "%U:%G" "$MONITOR_SCRIPT" | grep -q "[USER_DEV]:[GROUP_CORE]"; then
        check_pass "monitor.sh owner:group is [USER_DEV]:[GROUP_CORE]"
    else
        check_fail "monitor.sh owner:group is not [USER_DEV]:[GROUP_CORE]"
    fi

    if stat -c "%a" "$MONITOR_SCRIPT" | grep -q "750"; then
        check_pass "monitor.sh permissions are 750"
    else
        check_fail "monitor.sh permissions are not 750"
    fi

    # monitor.sh 실행 테스트
    echo "[INFO] Running monitor.sh test..."
    if sudo -u [USER_ADMIN] bash -c "$MONITOR_SCRIPT" 2>&1 | grep -q "SYSTEM MONITOR RESULT"; then
        check_pass "monitor.sh executes successfully"
    else
        check_warn "monitor.sh execution test inconclusive"
    fi
else
    check_fail "monitor.sh does not exist"
fi

# 8. 로그 파일 검증
echo ""
echo "--- 8. Log Files ---"
if [[ -f "[LOG_DIR]/monitor.log" ]]; then
    check_pass "monitor.log exists"

    # 로그 포맷 확인
    if head -1 "[LOG_DIR]/monitor.log" | grep -qE "^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\] PID:[0-9]+ CPU:[0-9.]+% MEM:[0-9.]+% DISK_USED:[0-9]+%$"; then
        check_pass "monitor.log format is correct"
    else
        check_warn "monitor.log format may be incorrect (or file is empty)"
    fi

    # 최근 로그 라인 수
    lines=$(wc -l < "[LOG_DIR]/monitor.log")
    echo "[INFO] monitor.log has $lines lines"
else
    check_fail "monitor.log does not exist"
fi

# 9. Cron 검증
echo ""
echo "--- 9. Cron Configuration ---"
if crontab -u [USER_ADMIN] -l 2>/dev/null | grep -q "monitor.sh"; then
    check_pass "Cron job for monitor.sh is registered"
else
    check_fail "Cron job for monitor.sh is not registered"
fi

# 10. logrotate 검증
echo ""
echo "--- 10. Logrotate Configuration ---"
if [[ -f "/etc/logrotate.d/agent-app" ]]; then
    check_pass "logrotate config exists"
    if grep -q "rotate 10" /etc/logrotate.d/agent-app && grep -q "size 10M" /etc/logrotate.d/agent-app; then
        check_pass "logrotate config has correct rotation settings"
    else
        check_warn "logrotate config may need adjustment"
    fi
else
    check_fail "logrotate config does not exist"
fi

# 결과 요약
echo ""
echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo -e "${GREEN}Passed: $PASS${NC}"
echo -e "${YELLOW}Warnings: $WARN${NC}"
echo -e "${RED}Failed: $FAIL${NC}"

if [[ $FAIL -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}All critical checks passed!${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}Some checks failed. Please review.${NC}"
    exit 1
fi