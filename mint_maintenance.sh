#!/usr/bin/env bash
set -euo pipefail

cleanup() {
  stty sane
}

trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [[ -f "$ENV_FILE" ]]; then
  while IFS='=' read -r key value; do
    # Skip empty lines and comments
    [[ -z "$key" || "$key" =~ ^# ]] && continue

    # Only set variable if NOT already set
    if [[ -z "${!key:-}" ]]; then
      export "$key=$value"
    fi
  done < "$ENV_FILE"
fi

LOG_FILE="${LOG_FILE:-$HOME/linux_maintenance.log}"

if [[ "$LOG_FILE" != /* ]]; then
  LOG_FILE="$HOME/$LOG_FILE"
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
  read -rp "Press Enter to continue..."
}

confirm() {
  local prompt="$1"
  read -rp "$prompt [y/N]: " reply
  [[ "${reply,,}" == "y" ]]
}

require_sudo() {
  sudo -v
}

show_disk_usage() {
  echo
  log "Disk usage:"
  df -h | tee -a "$LOG_FILE"

  echo
  log "Top-level usage in home:"
  du -h --max-depth=1 "$HOME" 2>/dev/null | sort -h | tee -a "$LOG_FILE"
}

system_update() {
  log "Running apt update/upgrade..."
  sudo apt update
  sudo apt upgrade -y
  log "System update completed."
}

remove_unused_packages() {
  log "Removing unused packages..."
  sudo apt autoremove -y
  sudo apt autoclean -y
  sudo apt clean
  log "Package cleanup completed."
}

clean_user_cache() {
  if confirm "Clear user cache (~/.cache/*)?"; then
    log "Clearing user cache..."
    rm -rf "$HOME/.cache/"*
    log "User cache cleared."
  else
    log "User cache cleanup skipped."
  fi
}

clean_thumbnails() {
  if [[ -d "$HOME/.cache/thumbnails" ]]; then
    if confirm "Clear thumbnail cache?"; then
      log "Clearing thumbnail cache..."
      rm -rf "$HOME/.cache/thumbnails/"*
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
    sudo journalctl --vacuum-time=7d
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
  log "Top 20 largest files in home:"
  find "$HOME" -type f -printf '%s %p\n' 2>/dev/null | sort -nr | head -n 20 | \
    awk '{ size=$1; $1=""; printf "%.2f MB %s\n", size/1024/1024, substr($0,2) }' | tee -a "$LOG_FILE"
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
  clear
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

main
