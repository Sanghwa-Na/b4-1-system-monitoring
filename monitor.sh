#!/bin/bash
# ============================================================
# monitor.sh - 시스템 상태 수집 및 로깅 스크립트
# ============================================================
# 위치: $AGENT_HOME/bin/monitor.sh
# 소유자: [USER_DEV]
# 그룹: [GROUP_CORE]
# 권한: 750 (rwxr-x---)
# cron 실행 계정: [USER_ADMIN] ([GROUP_CORE] 그룹 멤버이므로 실행 가능)
# ============================================================
# 기능:
# 1. Health Check (실패 시 exit 1)
#    - 프로세스: agent_app.py 실행 상태 확인
#    - 포트: TCP [APP_PORT] LISTEN 상태 확인
# 2. 상태 점검 (경고만 출력, 종료하지 않음)
#    - 방화벽(UFW) 활성화 상태 점검
# 3. 자원 수집
#    - CPU 사용률(%), 메모리 사용률(%), 디스크 사용률(Root partition, Used %)
# 4. 임계값 경고 (경고만 출력)
#    - CPU > 20%: [WARNING]
#    - MEM > 10%: [WARNING]
#    - DISK_USED > 80%: [WARNING]
# 5. 로그 기록
#    - 로그 파일: [LOG_DIR]/monitor.log
#    - 포맷: [YYYY-MM-DD HH:MM:SS] PID:... CPU:..% MEM:..% DISK_USED:..%
# 6. 로그 파일 용량 관리
#    - 최대 10MB / 10개 파일 유지 (logrotate 연동)
# ============================================================

set -euo pipefail

# 환경 변수 설정 (기본값)
AGENT_HOME="${AGENT_HOME:-[AGENT_HOME]}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-[LOG_DIR]}"
LOG_FILE="${AGENT_LOG_DIR}/monitor.log"
APP_NAME="agent_app.py"
APP_PORT=[APP_PORT]

# 로그 디렉토리 확인 및 생성
mkdir -p "${AGENT_LOG_DIR}"
if [[ ! -w "${AGENT_LOG_DIR}" ]]; then
    echo "[ERROR] Log directory not writable: ${AGENT_LOG_DIR}" >&2
    exit 1
fi

# 현재 타임스탬프 반환
timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# 앱 프로세스 PID 찾기
get_app_pid() {
    pgrep -f "${APP_NAME}" | head -1
}

# ============================================================
# 1. Health Check (실패 시 exit 1)
# ============================================================

# 프로세스 확인
check_process() {
    local pid
    pid=$(get_app_pid)
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
        echo "[HEALTH CHECK]"
        echo "Checking process '${APP_NAME}'... [OK] (PID: ${pid})"
        return 0
    else
        echo "[HEALTH CHECK]"
        echo "Checking process '${APP_NAME}'... [FAIL]"
        return 1
    fi
}

# 포트 확인
check_port() {
    if ss -tuln | grep -q ":${APP_PORT} "; then
        echo "Checking port ${APP_PORT}... [OK]"
        return 0
    else
        echo "Checking port ${APP_PORT}... [FAIL]"
        return 1
    fi
}

# ============================================================
# 2. 상태 점검 (경고만 출력)
# ============================================================

# 방화벽 상태 확인
check_firewall() {
    local fw_active=false
    if command -v ufw >/dev/null 2>&1; then
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            echo "[INFO] Firewall (UFW) is active"
            fw_active=true
        fi
    elif command -v firewall-cmd >/dev/null 2>&1; then
        if firewall-cmd --state 2>/dev/null | grep -q "running"; then
            echo "[INFO] Firewall (firewalld) is running"
            fw_active=true
        fi
    fi

    if [[ "${fw_active}" == "false" ]]; then
        echo "[WARNING] Firewall is inactive"
    fi
}

# ============================================================
# 3. 자원 수집
# ============================================================

collect_resources() {
    # CPU 사용률 계산
    local cpu_usage
    if command -v mpstat >/dev/null 2>&1; then
        cpu_usage=$(mpstat 1 1 2>/dev/null | awk '/Average:/ {printf "%.1f", 100 - $NF}')
    else
        # /proc/stat 방식 (fallback)
        local prev_idle prev_total
        read -r _ prev_idle prev_total <<< "$(awk '/^cpu / {print $5, $2+$3+$4+$5+$6+$7+$8+$9}' /proc/stat 2>/dev/null || echo "0 1")"
        sleep 0.5
        local idle total
        read -r _ idle total <<< "$(awk '/^cpu / {print $5, $2+$3+$4+$5+$6+$7+$8+$9}' /proc/stat 2>/dev/null || echo "0 1")"
        local diff_idle=$((idle - prev_idle))
        local diff_total=$((total - prev_total))
        if [[ ${diff_total} -gt 0 ]]; then
            cpu_usage=$(awk -v di="${diff_idle}" -v dt="${diff_total}" 'BEGIN {printf "%.1f", (1 - di/dt) * 100}')
        else
            cpu_usage="0.0"
        fi
    fi

    # 메모리 사용률
    local mem_usage
    mem_usage=$(free | awk '/^Mem:/ {printf "%.1f", $3/$2 * 100}')

    # 디스크 사용률 (root 파티션)
    local disk_usage
    disk_usage=$(df / | awk 'NR==2 {gsub(/%/, "", $5); print $5}')

    echo "${cpu_usage} ${mem_usage} ${disk_usage}"
}

# ============================================================
# 4. 임계값 경고
# ============================================================

check_thresholds() {
    local cpu=$1
    local mem=$2
    local disk=$3

    # CPU > 20%
    if (( $(echo "${cpu} > 20" | bc -l 2>/dev/null || echo 0) )); then
        echo "[WARNING] CPU threshold exceeded (${cpu}% > 20%)"
    fi

    # MEM > 10%
    if (( $(echo "${mem} > 10" | bc -l 2>/dev/null || echo 0) )); then
        echo "[WARNING] MEM threshold exceeded (${mem}% > 10%)"
    fi

    # DISK_USED > 80%
    if [[ ${disk} -gt 80 ]]; then
        echo "[WARNING] DISK threshold exceeded (${disk}% > 80%)"
    fi
}

# ============================================================
# 5. 로그 기록
# ============================================================

write_log() {
    local pid=$1
    local cpu=$2
    local mem=$3
    local disk=$4
    local ts
    ts=$(timestamp)
    echo "[${ts}] PID:${pid} CPU:${cpu}% MEM:${mem}% DISK_USED:${disk}%" >> "${LOG_FILE}"
}

# ============================================================
# 6. 로그 파일 용량 관리 (logrotate가 주 관리, 여기선 보조)
# ============================================================

manage_log_size() {
    local max_size=$((10 * 1024 * 1024))  # 10MB
    local max_files=10

    if [[ -f "${LOG_FILE}" ]]; then
        local file_size
        file_size=$(stat -c%s "${LOG_FILE}" 2>/dev/null || stat -f%z "${LOG_FILE}" 2>/dev/null || echo 0)
        if [[ ${file_size} -gt ${max_size} ]]; then
            # 로그 로테이션 (단순 구현)
            for i in $(seq $((max_files - 1)) -1 1); do
                if [[ -f "${LOG_FILE}.${i}" ]]; then
                    mv "${LOG_FILE}.${i}" "${LOG_FILE}.$((i + 1))"
                fi
            done
            mv "${LOG_FILE}" "${LOG_FILE}.1"
            touch "${LOG_FILE}"
            chown [USER_ADMIN]:[GROUP_CORE] "${LOG_FILE}" 2>/dev/null || true
            chmod 660 "${LOG_FILE}" 2>/dev/null || true
        fi
    fi
}

# ============================================================
# 메인 실행
# ============================================================

main() {
    echo "====== SYSTEM MONITOR RESULT ======"

    # [HEALTH CHECK] - 실패 시 exit 1
    local pid
    pid=$(get_app_pid)

    if ! check_process; then
        exit 1
    fi

    if ! check_port; then
        exit 1
    fi

    # [RESOURCE MONITORING]
    echo "[RESOURCE MONITORING]"

    # 방화벽 체크 (경고만)
    check_firewall

    # 리소스 수집
    read -r cpu_usage mem_usage disk_usage <<< "$(collect_resources)"

    echo "CPU Usage : ${cpu_usage}%"
    echo "MEM Usage : ${mem_usage}%"
    echo "DISK Used  : ${disk_usage}%"

    # 임계값 경고
    check_thresholds "${cpu_usage}" "${mem_usage}" "${disk_usage}"

    # 로그 기록
    write_log "${pid}" "${cpu_usage}" "${mem_usage}" "${disk_usage}"

    # 로그 용량 관리
    manage_log_size

    echo "[INFO] Log appended: ${LOG_FILE}"
}

main "$@"