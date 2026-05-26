#!/usr/bin/env bash
set -euo pipefail

# Install/update all Kafkade agent skills to user-level skills directories.
# Installs to ~/.copilot/skills/, ~/.claude/skills/, and ~/.agents/skills/
# so skills work with Copilot CLI, Claude Code, and any agent supporting the
# Agent Skills open standard.
#
# Usage: ./install.sh [--uninstall]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="${SCRIPT_DIR}/skills"

TARGETS=(
    "${COPILOT_HOME:-${HOME}/.copilot}/skills"
    "${CLAUDE_HOME:-${HOME}/.claude}/skills"
    "${HOME}/.agents/skills"
)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

info()  { printf "${GREEN}✔${RESET} %s\n" "$1"; }
warn()  { printf "${YELLOW}!${RESET} %s\n" "$1"; }
error() { printf "${RED}✖${RESET} %s\n" "$1" >&2; }

uninstall=false
if [[ "${1:-}" == "--uninstall" ]]; then
    uninstall=true
fi

if [[ ! -d "${SKILLS_SRC}" ]]; then
    error "Skills directory not found: ${SKILLS_SRC}"
    exit 1
fi

# Discover all skills (directories containing SKILL.md)
skills=()
for skill_md in "${SKILLS_SRC}"/*/SKILL.md; do
    [[ -f "${skill_md}" ]] || continue
    skill_dir="$(dirname "${skill_md}")"
    skill_name="$(basename "${skill_dir}")"
    skills+=("${skill_name}")
done

if [[ ${#skills[@]} -eq 0 ]]; then
    warn "No skills found in ${SKILLS_SRC}"
    exit 0
fi

printf "\n${BOLD}Kafkade Agent Skills${RESET}\n\n"

for target in "${TARGETS[@]}"; do
    printf "${DIM}→ %s${RESET}\n" "${target}"

    if $uninstall; then
        for skill in "${skills[@]}"; do
            if [[ -d "${target}/${skill}" ]]; then
                rm -rf "${target}/${skill}"
                info "Removed ${skill}"
            else
                warn "Not installed: ${skill}"
            fi
        done
    else
        mkdir -p "${target}"
        for skill in "${skills[@]}"; do
            src="${SKILLS_SRC}/${skill}"
            dst="${target}/${skill}"
            if [[ -d "${dst}" ]]; then
                rm -rf "${dst}"
                cp -R "${src}" "${dst}"
                info "Updated ${skill}"
            else
                cp -R "${src}" "${dst}"
                info "Installed ${skill}"
            fi
        done
    fi
    echo
done

if $uninstall; then
    printf "Done. Restart your agent or run ${BOLD}/skills reload${RESET} to apply.\n"
else
    printf "${BOLD}%d skill(s)${RESET} installed to %d targets.\n" "${#skills[@]}" "${#TARGETS[@]}"
    printf "Restart your agent or run ${BOLD}/skills reload${RESET} to apply.\n"
fi
