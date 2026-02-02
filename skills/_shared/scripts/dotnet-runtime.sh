#!/usr/bin/env bash

# Shared .NET runtime helpers for skills.
# Expects step/ok/warn/err logging functions in the caller (fallbacks used if missing).

_dotnet_log() {
  local level="$1"
  shift
  if declare -f "$level" >/dev/null 2>&1; then
    "$level" "$@"
    return
  fi

  case "$level" in
    step)
      echo ""
      echo ">> $*"
      ;;
    ok)
      echo "   OK: $*"
      ;;
    warn)
      echo "   WARN: $*"
      ;;
    err)
      echo "   ERROR: $*" >&2
      ;;
    *)
      echo "$*"
      ;;
  esac
}

dotnet_runtime_env() {
  local install_dir="${DOTNET_INSTALL_DIR:-"$HOME/.dotnet"}"
  DOTNET_INSTALL_DIR="$install_dir"
  export DOTNET_INSTALL_DIR
  export DOTNET_ROOT="$install_dir"
  export DOTNET_ROOT_X64="$install_dir"

  case ":$PATH:" in
    *":$install_dir:"*)
      ;;
    *)
      export PATH="$install_dir:$PATH"
      ;;
  esac
}

dotnet_runtime_persist() {
  local install_dir="${DOTNET_INSTALL_DIR:-"$HOME/.dotnet"}"
  local marker="# Added by Codex dotnet runtime"
  local line_root="export DOTNET_ROOT=\"$install_dir\""
  local line_root_x64="export DOTNET_ROOT_X64=\"$install_dir\""
  local line_path="export PATH=\"$install_dir:\$PATH\""
  local targets=("$HOME/.bashrc" "$HOME/.profile")

  if [[ -n "${ZSH_VERSION:-}" || "${SHELL:-}" == *zsh ]]; then
    targets+=("$HOME/.zshrc")
  fi

  for target in "${targets[@]}"; do
    if [[ -e "$target" && ! -w "$target" ]]; then
      _dotnet_log warn "Cannot update $target (not writable)"
      continue
    fi
    if [[ ! -e "$target" && -n "${HOME:-}" && ! -w "$HOME" ]]; then
      _dotnet_log warn "Cannot create $target (home not writable)"
      continue
    fi
    if [[ -f "$target" ]] && grep -q "$marker" "$target" 2>/dev/null; then
      continue
    fi
    if grep -q "$install_dir" "$target" 2>/dev/null; then
      continue
    fi
    {
      echo ""
      echo "$marker"
      echo "$line_root"
      echo "$line_root_x64"
      echo "$line_path"
    } >> "$target"
  done
}

ensure_dotnet_runtime() {
  dotnet_runtime_env
  dotnet_runtime_persist

  local channel="${DOTNET_CHANNEL:-10.0}"
  local required_major="${DOTNET_REQUIRED_MAJOR:-${channel%%.*}}"
  if [[ -z "$required_major" ]]; then
    required_major="0"
  fi

  if command -v dotnet >/dev/null 2>&1; then
    local version
    version="$(dotnet --version 2>/dev/null || echo "0.0.0")"
    local major="${version%%.*}"
    if [[ "$major" -ge "$required_major" ]]; then
      _dotnet_log ok ".NET SDK $version detected"
      return 0
    fi
    _dotnet_log warn ".NET SDK $version found, but ${required_major}.0+ is required"
  else
    _dotnet_log warn ".NET SDK not found"
  fi

  _dotnet_log step "Installing .NET SDK $channel"

  if ! command -v curl >/dev/null 2>&1; then
    _dotnet_log err "curl is required to install .NET. Install curl and rerun this script."
    return 2
  fi

  local installer
  installer="$(mktemp)"
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$installer"
  bash "$installer" --channel "$channel" --install-dir "$DOTNET_INSTALL_DIR"
  rm -f "$installer"

  _dotnet_log ok ".NET SDK installed to $DOTNET_INSTALL_DIR"
  _dotnet_log warn "Add $DOTNET_INSTALL_DIR to your PATH for future shells"
}
