#!/usr/bin/env bash

# Shared .NET environment helpers for skills.
# Expects step/ok/warn/err logging functions in the caller (fallbacks used if missing).

dotnet_env() {
  local install_dir="${DOTNET_INSTALL_DIR:-"$HOME/.dotnet"}"
  DOTNET_INSTALL_DIR="$install_dir"
  export DOTNET_INSTALL_DIR
  export DOTNET_ROOT="$install_dir"
  export DOTNET_ROOT_X64="$install_dir"
  export PATH="$install_dir:$install_dir/tools:$PATH"
}

_dotnet_should_persist() {
  case "${DOTNET_PERSIST_PATH:-1}" in
    0|false|False|FALSE|no|No|NO)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

dotnet_env_persist() {
  local install_dir="${DOTNET_INSTALL_DIR:-"$HOME/.dotnet"}"
  local tools_dir="$install_dir/tools"
  local marker="# Added by Codex dotnet setup"
  local line_root="export DOTNET_ROOT=\"$install_dir\""
  local line_root_x64="export DOTNET_ROOT_X64=\"$install_dir\""
  local line_path="export PATH=\"$install_dir:$tools_dir:\$PATH\""
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
    if ! grep -q "$tools_dir" "$target" 2>/dev/null; then
      {
        echo ""
        echo "$marker"
        echo "$line_root"
        echo "$line_root_x64"
        echo "$line_path"
      } >> "$target"
    fi
  done
}

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

ensure_dotnet() {
  dotnet_env
  if _dotnet_should_persist; then
    dotnet_env_persist
  fi

  local channel="${DOTNET_CHANNEL:-10.0}"

  if command -v dotnet >/dev/null 2>&1; then
    local version
    version="$(dotnet --version 2>/dev/null || echo "0.0.0")"
    local major="${version%%.*}"
    if [[ "$major" -ge 10 ]]; then
      _dotnet_log ok ".NET SDK $version detected"
      return 0
    fi
    _dotnet_log warn ".NET SDK $version found, but 10.0+ is required"
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
  _dotnet_log warn "Add $DOTNET_INSTALL_DIR and $DOTNET_INSTALL_DIR/tools to your PATH for future shells"
}
