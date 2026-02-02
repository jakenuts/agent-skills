#!/usr/bin/env bash

# Shared .NET global tool helpers for skills.
# Expects step/ok/warn/err logging functions in the caller (fallbacks used if missing).

DOTNET_RUNTIME_HELPER="${DOTNET_RUNTIME_HELPER:-"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dotnet-runtime.sh"}"
if [[ ! -f "$DOTNET_RUNTIME_HELPER" ]]; then
  echo "   ERROR: Shared dotnet runtime helper not found: $DOTNET_RUNTIME_HELPER" >&2
  return 2 2>/dev/null || exit 2
fi

# shellcheck source=dotnet-runtime.sh
source "$DOTNET_RUNTIME_HELPER"

dotnet_tools_env() {
  dotnet_runtime_env

  local tools_dir="$DOTNET_INSTALL_DIR/tools"
  case ":$PATH:" in
    *":$tools_dir:"*)
      ;;
    *)
      export PATH="$tools_dir:$PATH"
      ;;
  esac
}

dotnet_tools_persist() {
  local install_dir="${DOTNET_INSTALL_DIR:-"$HOME/.dotnet"}"
  local tools_dir="$install_dir/tools"
  local marker="# Added by Codex dotnet tools"
  local line_path="export PATH=\"$tools_dir:\$PATH\""
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
    if grep -q "$tools_dir" "$target" 2>/dev/null; then
      continue
    fi
    {
      echo ""
      echo "$marker"
      echo "$line_path"
    } >> "$target"
  done
}

ensure_dotnet_tools_env() {
  dotnet_tools_env
  dotnet_tools_persist
}

install_dotnet_tool() {
  local package_id="${1:-}"
  local version="${2:-}"
  local tools_dir="${3:-}"
  local command_name="${4:-}"

  if [[ -z "$package_id" ]]; then
    _dotnet_log err "Missing .NET tool package id"
    return 2
  fi

  if [[ -n "$tools_dir" && ! -d "$tools_dir" ]]; then
    _dotnet_log err "Tool package directory not found: $tools_dir"
    return 2
  fi

  if dotnet tool list --global 2>/dev/null | grep -qi "$package_id"; then
    _dotnet_log ok "Tool already installed: $package_id"
    return 0
  fi

  _dotnet_log step "Installing $package_id${version:+ v$version}"

  local args=("--global")
  if [[ -n "$version" ]]; then
    args+=("--version" "$version")
  fi
  if [[ -n "$tools_dir" ]]; then
    args+=("--add-source" "$tools_dir")
  fi

  dotnet tool install "$package_id" "${args[@]}"

  if [[ -n "$command_name" ]]; then
    if command -v "$command_name" >/dev/null 2>&1; then
      _dotnet_log ok "Tool installed: $command_name"
    else
      _dotnet_log warn "Tool installed but '$command_name' is not on PATH. Restart your shell and try again."
    fi
  fi
}
