#!/usr/bin/env bash
set -euo pipefail

# User whose home directory should be maintained.
TARGET_USER="${TARGET_USER:-${SUDO_USER:-$(id -un)}}"
TARGET_HOME="${TARGET_HOME:-$(getent passwd "$TARGET_USER" | cut -d: -f6)}"

AUTO_MODE=false

if [[ "${1:-}" == "--auto" ]]; then
  AUTO_MODE=true
fi


cleanup() {
  # stty requires an interactive terminal.
  if [[ -t 0 ]]; then
    stty sane
  fi
}

trap cleanup EXIT


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [[ -f "$ENV_FILE" ]]; then
  while IFS='=' read -r key value; do
    # Skip empty lines and comments.
    [[ -z "$key" || "$key" =~ ^# ]] && continue

    # Only set variable if not already set.
    if [[ -z "${!key:-}" ]]; then
      export "$key=$value"
    fi
  done < "$ENV_FILE"
fi


LOG_FILE="${LOG_FILE:-$TARGET_HOME/linux_maintenance.log}"

if [[ "$LOG_FILE" != /* ]]; then
  LOG_FILE="$TARGET_HOME/$LOG_FILE"
fi


print_header() {
  echo
  echo "========================================"
  echo " Linux Mint Maintenance Utility"
  echo "========================================"
  echo
}


log() {
  local msg="$1"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" | tee -a "$LOG_FILE"
}


pause() {
  if [[ "$AUTO_MODE" == false ]]; then
    read -rp "Press Enter to continue..."
  fi
}


confirm() {
  local prompt="$1"

  # Automatic systemd execution:
  # automatically approve maintenance operations.
  if [[ "$AUTO_MODE" == true ]]; then
    return 0
  fi

  read -rp "$prompt [y/N]: " reply
  [[ "${reply,,}" == "y" ]]
}


require_sudo() {
  if [[ "$EUID" -eq 0 ]]; then
    return 0
  fi

  sudo -v
}


show_disk_usage() {
  echo
  log "Disk usage:"
  df -h | tee -a "$LOG_FILE"

  echo
  log "Top-level usage in $TARGET_HOME:"
  du -h --max-depth=1 "$TARGET_HOME" 2>/dev/null \
    | sort -h \
    | tee -a "$LOG_FILE"
}


system_update() {
  log "Running apt update/upgrade..."

  if [[ "$EUID" -eq 0 ]]; then
    apt-get update
    apt-get upgrade -y
  else
    sudo apt-get update
    sudo apt-get upgrade -y
  fi

  log "System update completed."
}


remove_unused_packages() {
  log "Removing unused packages..."

  if [[ "$EUID" -eq 0 ]]; then
    apt-get autoremove -y
    apt-get autoclean -y
    apt-get clean
  else
    sudo apt-get autoremove -y
    sudo apt-get autoclean -y
    sudo apt-get clean
  fi

  log "Package cleanup completed."
}


clean_user_cache() {
  if confirm "Clear user cache ($TARGET_HOME/.cache/*)?"; then
    log "Clearing user cache..."

    rm -rf "$TARGET_HOME/.cache/"*

    log "User cache cleared."
  else
    log "User cache cleanup skipped."
  fi
}


clean_thumbnails() {
  if [[ -d "$TARGET_HOME/.cache/thumbnails" ]]; then
    if confirm "Clear thumbnail cache?"; then
      log "Clearing thumbnail cache..."

      rm -rf "$TARGET_HOME/.cache/thumbnails/"*

      log "Thumbnail cache cleared."
    else
      log "Thumbnail cache cleanup skipped."
    fi
  fi
}


clean_journal_logs() {
  if ! command -v journalctl >/dev/null 2>&1; then
    log "journalctl not available (skipping)"
    return
  fi

  if confirm "Clean journal logs older than 7 days?"; then
    log "Cleaning journal logs..."

    if [[ "$EUID" -eq 0 ]]; then
      journalctl --vacuum-time=7d
    else
      sudo journalctl --vacuum-time=7d
    fi

    log "Journal cleanup completed."
  else
    log "Journal cleanup skipped."
  fi
}


docker_cleanup() {
  if ! command -v docker >/dev/null 2>&1; then
    log "Docker not installed. Skipping."
    return
  fi

  if confirm "Run Docker cleanup?"; then
    log "Running Docker system prune..."

    docker system prune -f

    log "Docker cleanup completed."
  else
    log "Docker cleanup skipped."
  fi
}


show_large_files() {
  echo
  log "Top 20 largest files in $TARGET_HOME:"

  find "$TARGET_HOME" -type f -printf '%s %p\n' 2>/dev/null \
    | sort -nr \
    | sed -n '1,20p' \
    | awk '{
        size=$1;
        $1="";
        printf "%.2f MB %s\n", size/1024/1024, substr($0,2)
      }' \
    | tee -a "$LOG_FILE"
}


full_maintenance() {
  require_sudo

  show_disk_usage

  if confirm "Run system update?"; then
    system_update
  else
    log "System update skipped."
  fi

  if confirm "Run APT cleanup?"; then
    remove_unused_packages
  else
    log "APT cleanup skipped."
  fi

  clean_journal_logs
  clean_user_cache
  clean_thumbnails
  docker_cleanup

  show_disk_usage
  show_large_files

  log "Maintenance completed."
}


show_menu() {
  if [[ -t 1 ]]; then
    clear
  fi

  print_header

  echo "1) Full maintenance"
  echo "2) Show disk usage"
  echo "3) System update"
  echo "4) APT cleanup"
  echo "5) Clear user cache"
  echo "6) Clean journal logs"
  echo "7) Docker cleanup"
  echo "8) Show largest files"
  echo "0) Exit"
  echo
}


main() {
  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE"

  if [[ "$AUTO_MODE" == true ]]; then
    log "Starting automatic weekly maintenance."
    full_maintenance
    log "Automatic weekly maintenance finished."
    return
  fi

  while true; do
    show_menu

    read -rp "Choose an option: " choice

    case "$choice" in
      1) full_maintenance; pause ;;
      2) show_disk_usage; pause ;;
      3) require_sudo; system_update; pause ;;
      4) require_sudo; remove_unused_packages; pause ;;
      5) clean_user_cache; pause ;;
      6) require_sudo; clean_journal_logs; pause ;;
      7) docker_cleanup; pause ;;
      8) show_large_files; pause ;;
      0) log "Exiting."; exit 0 ;;
      *) echo "Invalid option"; pause ;;
    esac
  done
}


main "$@"
