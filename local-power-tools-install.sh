#!/usr/bin/env bash
# local-power-tools-install.sh — install agent-browser + the local-power-tools toolchain.
#
# Universal installer. Works on macOS (Homebrew), Debian/Ubuntu (apt),
# Fedora/RHEL (dnf), and Arch (pacman). Falls back to cargo or npm for
# tools that aren't packaged everywhere. Skips tools already on PATH.
#
# Usage:
#   ./local-power-tools-install.sh                     # install everything that's missing
#   ./local-power-tools-install.sh --list              # show every tool and its current status
#   ./local-power-tools-install.sh --dry-run           # print the commands without running them
#   ./local-power-tools-install.sh --only ast-grep,sd  # install only the listed tools
#   ./local-power-tools-install.sh --skip biome,vips   # install everything except the listed tools
#   ./local-power-tools-install.sh --no-agent-browser  # skip agent-browser (power tools only)
#   ./local-power-tools-install.sh --yes               # don't prompt before installing
#   ./local-power-tools-install.sh --help              # this message

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Tool catalog
#
# Edit this table to add/remove tools. Each entry maps the binary name (what
# `command -v` checks) to package names per platform plus a language-pm
# fallback. An empty field means "no native package on this platform — use
# the fallback."
# ─────────────────────────────────────────────────────────────────────────────

TOOLS=(
  # binary       brew              apt                       dnf                       pacman       fallback
  "ast-grep    | ast-grep        |                          |                          | ast-grep   | cargo:ast-grep"
  "difft       | difftastic      | difftastic               | difftastic               | difftastic | cargo:difftastic"
  "sd          | sd              | sd                       |                          | sd         | cargo:sd"
  "comby       | comby           |                          |                          |            | manual:https://github.com/comby-tools/comby/releases"
  "scc         | scc             |                          |                          | scc        | go:github.com/boyter/scc/v3"
  "yq          | yq              | yq                       | yq                       | go-yq      | binary:https://github.com/mikefarah/yq/releases/latest"
  "shellcheck  | shellcheck      | shellcheck               | ShellCheck               | shellcheck | manual:https://github.com/koalaman/shellcheck#installing"
  "hyperfine   | hyperfine       | hyperfine                | hyperfine                | hyperfine  | cargo:hyperfine"
  "watchexec   | watchexec       | watchexec                |                          | watchexec  | cargo:watchexec-cli"
  "vips        | vips            | libvips-tools            | vips-tools               | libvips    | manual:https://www.libvips.org/install.html"
  "ffmpeg      | ffmpeg          | ffmpeg                   | ffmpeg                   | ffmpeg     | manual:https://ffmpeg.org/download.html"
  "odiff       | odiff-bin       |                          |                          |            | npm:odiff-bin"
  "aria2c      | aria2           | aria2                    | aria2                    | aria2      | manual:https://aria2.github.io/"
  "yt-dlp      | yt-dlp          | yt-dlp                   | yt-dlp                   | yt-dlp     | binary:https://github.com/yt-dlp/yt-dlp/releases/latest"
  "htmlq       | htmlq           |                          |                          |            | cargo:htmlq"
  "exiftool    | exiftool        | libimage-exiftool-perl   | perl-Image-ExifTool      | perl-image-exiftool | manual:https://exiftool.org/install.html"
  "biome       | biome           |                          |                          |            | npm:@biomejs/biome"
)

AGENT_BROWSER_PKG="agent-browser"   # installed via npm install -g

# ─────────────────────────────────────────────────────────────────────────────
# Flag parsing
# ─────────────────────────────────────────────────────────────────────────────

DRY_RUN=0
LIST_ONLY=0
ASSUME_YES=0
SKIP_AB=0
ONLY_LIST=""
SKIP_LIST=""

print_help() {
  sed -n '2,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)         DRY_RUN=1 ;;
    --list)            LIST_ONLY=1 ;;
    --yes|-y)          ASSUME_YES=1 ;;
    --no-agent-browser) SKIP_AB=1 ;;
    --only)            ONLY_LIST="${2:?--only needs a value}"; shift ;;
    --only=*)          ONLY_LIST="${1#*=}" ;;
    --skip)            SKIP_LIST="${2:?--skip needs a value}"; shift ;;
    --skip=*)          SKIP_LIST="${1#*=}" ;;
    -h|--help)         print_help; exit 0 ;;
    *)                 echo "unknown flag: $1" >&2; print_help; exit 2 ;;
  esac
  shift
done

# ─────────────────────────────────────────────────────────────────────────────
# Platform detection
# ─────────────────────────────────────────────────────────────────────────────

PLATFORM=""
PM=""
case "$(uname -s)" in
  Darwin)
    PLATFORM=macos
    PM=brew
    ;;
  Linux)
    PLATFORM=linux
    if   command -v apt-get >/dev/null 2>&1; then PM=apt
    elif command -v dnf     >/dev/null 2>&1; then PM=dnf
    elif command -v pacman  >/dev/null 2>&1; then PM=pacman
    else PM=""
    fi
    ;;
  *)
    PLATFORM="$(uname -s)"
    PM=""
    ;;
esac

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

c_reset=$'\033[0m'
c_bold=$'\033[1m'
c_dim=$'\033[2m'
c_green=$'\033[32m'
c_yellow=$'\033[33m'
c_red=$'\033[31m'
c_cyan=$'\033[36m'

say()  { printf '%s\n' "$*"; }
note() { printf '%s%s%s\n' "$c_dim" "$*" "$c_reset"; }
ok()   { printf '%s✓%s %s\n' "$c_green" "$c_reset" "$*"; }
warn() { printf '%s!%s %s\n' "$c_yellow" "$c_reset" "$*"; }
err()  { printf '%s✗%s %s\n' "$c_red"    "$c_reset" "$*"; }
head() { printf '\n%s%s%s\n' "$c_bold" "$*" "$c_reset"; }

run() {
  # Commands are intentionally passed as a single shell string so we can
  # handle pipes, sudo, and subshells uniformly. eval is the right tool.
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '  %s$ %s%s\n' "$c_cyan" "$1" "$c_reset"
  else
    printf '  %s$ %s%s\n' "$c_cyan" "$1" "$c_reset"
    eval "$1"
  fi
}

confirm() {
  [[ $ASSUME_YES -eq 1 ]] && return 0
  read -r -p "$1 [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

in_list() {
  # $1 = needle, $2 = comma-separated haystack
  [[ -z "$2" ]] && return 1
  local IFS=,
  for item in $2; do
    [[ "$item" == "$1" ]] && return 0
  done
  return 1
}

# parse one TOOLS row → sets BIN, BREW, APT, DNF, PACMAN, FALLBACK
parse_row() {
  local row="$1" IFS='|' parts
  read -ra parts <<<"$row"
  BIN="$(echo "${parts[0]:-}" | xargs)"
  BREW="$(echo "${parts[1]:-}" | xargs)"
  APT="$(echo "${parts[2]:-}" | xargs)"
  DNF="$(echo "${parts[3]:-}" | xargs)"
  PACMAN="$(echo "${parts[4]:-}" | xargs)"
  FALLBACK="$(echo "${parts[5]:-}" | xargs)"
}

# decide install command for current platform; echoes the shell command, or
# prints nothing (and a warning) if there's no automatic install path.
plan_install() {
  case "$PM" in
    brew)   [[ -n "$BREW"   ]] && { echo "brew install $BREW"; return; } ;;
    apt)    [[ -n "$APT"    ]] && { echo "sudo apt-get install -y $APT"; return; } ;;
    dnf)    [[ -n "$DNF"    ]] && { echo "sudo dnf install -y $DNF"; return; } ;;
    pacman) [[ -n "$PACMAN" ]] && { echo "sudo pacman -S --noconfirm $PACMAN"; return; } ;;
  esac
  # Fall back to language pm
  case "$FALLBACK" in
    cargo:*)  echo "cargo install --locked ${FALLBACK#cargo:}"; return ;;
    npm:*)    echo "npm install -g ${FALLBACK#npm:}"; return ;;
    go:*)     echo "go install ${FALLBACK#go:}@latest"; return ;;
    binary:*) echo "# Download a release binary from: ${FALLBACK#binary:}"; return ;;
    manual:*) echo "# Install manually — see: ${FALLBACK#manual:}"; return ;;
  esac
  echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# --list mode
# ─────────────────────────────────────────────────────────────────────────────

if [[ $LIST_ONLY -eq 1 ]]; then
  head "Detected platform: $PLATFORM ($PM)"
  printf '\n%-12s %-10s %s\n' "TOOL" "STATUS" "PLANNED INSTALL"
  printf '%-12s %-10s %s\n' "----" "------" "---------------"
  for row in "${TOOLS[@]}"; do
    parse_row "$row"
    if command -v "$BIN" >/dev/null 2>&1; then
      status="${c_green}installed${c_reset}"
      plan="$(command -v "$BIN")"
    else
      status="${c_yellow}missing${c_reset}"
      plan="$(plan_install)"
      [[ -z "$plan" ]] && plan="${c_red}no install path${c_reset}"
    fi
    printf '%-12s %b%-10s%b %s\n' "$BIN" "" "$status" "" "$plan"
  done
  # agent-browser status
  printf '\n%-12s ' "agent-browser"
  if command -v agent-browser >/dev/null 2>&1; then
    printf '%binstalled%b %s\n' "$c_green" "$c_reset" "$(command -v agent-browser)"
  else
    printf '%bmissing%b npm install -g %s\n' "$c_yellow" "$c_reset" "$AGENT_BROWSER_PKG"
  fi
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Install mode
# ─────────────────────────────────────────────────────────────────────────────

head "agent-browser + local-power-tools installer"
say  "Platform: $PLATFORM   Package manager: ${PM:-<none detected>}"

# Sanity checks per platform
if [[ "$PLATFORM" == macos && -z "$PM" ]]; then
  err "Homebrew not found. Install it first:"
  # shellcheck disable=SC2016  # we want this literal, not expanded
  say '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  exit 1
fi
if [[ "$PLATFORM" == linux && -z "$PM" ]]; then
  warn "No supported package manager (apt/dnf/pacman) found. The script will use cargo/npm fallbacks where possible — install Rust + Node first if you don't have them."
fi
if [[ "$PLATFORM" != macos && "$PLATFORM" != linux ]]; then
  warn "Unrecognized platform: $PLATFORM. The script will print install commands but you may need to adapt them."
fi

PLANNED=()
PLANNED_CMDS=()

for row in "${TOOLS[@]}"; do
  parse_row "$row"

  # Filter by --only / --skip
  if [[ -n "$ONLY_LIST" ]] && ! in_list "$BIN" "$ONLY_LIST"; then continue; fi
  if [[ -n "$SKIP_LIST" ]] &&   in_list "$BIN" "$SKIP_LIST"; then continue; fi

  if command -v "$BIN" >/dev/null 2>&1; then
    ok "$BIN already installed ($(command -v "$BIN"))"
    continue
  fi

  cmd="$(plan_install)"
  if [[ -z "$cmd" ]]; then
    err "$BIN: no install path for $PM and no fallback configured."
    continue
  fi

  PLANNED+=("$BIN")
  PLANNED_CMDS+=("$cmd")
done

# agent-browser
AB_PLAN=""
if [[ $SKIP_AB -eq 0 ]] && { [[ -z "$ONLY_LIST" ]] || in_list "agent-browser" "$ONLY_LIST"; } \
   && ! in_list "agent-browser" "$SKIP_LIST"; then
  if command -v agent-browser >/dev/null 2>&1; then
    ok "agent-browser already installed ($(command -v agent-browser))"
  elif ! command -v npm >/dev/null 2>&1; then
    err "agent-browser needs npm. Install Node.js (https://nodejs.org/) and re-run."
  else
    AB_PLAN="npm install -g $AGENT_BROWSER_PKG"
    PLANNED+=("agent-browser")
    PLANNED_CMDS+=("$AB_PLAN")
  fi
fi

if [[ ${#PLANNED[@]} -eq 0 ]]; then
  head "Nothing to install. ✨"
  exit 0
fi

head "Planned installs (${#PLANNED[@]}):"
for i in "${!PLANNED[@]}"; do
  printf '  %-14s %s%s%s\n' "${PLANNED[$i]}" "$c_dim" "${PLANNED_CMDS[$i]}" "$c_reset"
done

if [[ $DRY_RUN -eq 1 ]]; then
  head "Dry run — no changes made."
  exit 0
fi

if ! confirm "Proceed with these installs?"; then
  warn "Aborted by user."
  exit 1
fi

head "Installing…"
FAILED=()
for i in "${!PLANNED[@]}"; do
  bin="${PLANNED[$i]}"
  cmd="${PLANNED_CMDS[$i]}"
  say ""
  say "── $bin ──"
  # Commands starting with '#' are manual-install notes
  if [[ "$cmd" == \#* ]]; then
    warn "$bin: no automatic install on this platform."
    say  "  ${cmd#\# }"
    FAILED+=("$bin (manual)")
    continue
  fi
  if run "$cmd"; then
    if command -v "$bin" >/dev/null 2>&1; then
      ok "$bin installed."
    else
      warn "$bin: command not on PATH after install. Check your shell profile."
      FAILED+=("$bin (PATH)")
    fi
  else
    err "$bin: install command failed."
    FAILED+=("$bin (failed)")
  fi
done

head "Summary"
say "  installed: $((${#PLANNED[@]} - ${#FAILED[@]})) / ${#PLANNED[@]}"
if [[ ${#FAILED[@]} -gt 0 ]]; then
  warn "needs attention:"
  for f in "${FAILED[@]}"; do say "  - $f"; done
  exit 1
fi
ok "All planned tools installed."

# Post-install: agent-browser one-time Chrome setup
if [[ -n "$AB_PLAN" ]] && command -v agent-browser >/dev/null 2>&1; then
  head "agent-browser one-time setup"
  say "Running 'agent-browser install' to fetch a Chrome-for-Testing build…"
  run "agent-browser install"
  say ""
  say "Run 'agent-browser doctor' if you hit any issues."
fi
