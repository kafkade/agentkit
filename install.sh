#!/usr/bin/env bash
set -euo pipefail

# Install, update, or uninstall Kafkade agent skills in user-level skills
# directories so skills work with Copilot CLI, Claude Code, and any agent
# supporting the Agent Skills open standard.
#
# Runs an interactive, two-step installer:
#   1. Select skills: a checkbox list with available version, installed
#      version, and status. New and outdated skills are preselected.
#   2. Select targets: a checkbox list of agent skills directories, each
#      showing what would change there.
# It then shows a summary and asks for confirmation.
#
# Targets:
#   copilot: ~/.copilot/skills/  (or $COPILOT_HOME/skills/)
#   claude:  ~/.claude/skills/   (or $CLAUDE_HOME/skills/)
#   agents:  ~/.agents/skills/   (vendor-neutral)
#
# Passing skill names or --all skips the menus. When stdin is not a terminal,
# all skills are processed. Without --target, these modes use all targets.
#
# Usage: ./install.sh [--all] [--list] [--uninstall] [--target t1,t2] [skill ...]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="${SCRIPT_DIR}/skills"

TARGET_IDS=(copilot claude agents)
TARGET_LABELS=("GitHub Copilot" "Claude Code" "Agents (vendor-neutral)")
TARGETS=(
    "${COPILOT_HOME:-${HOME}/.copilot}/skills"
    "${CLAUDE_HOME:-${HOME}/.claude}/skills"
    "${HOME}/.agents/skills"
)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

info()  { printf "${GREEN}✔${RESET} %s\n" "$1"; }
warn()  { printf "${YELLOW}!${RESET} %s\n" "$1"; }
error() { printf "${RED}✖${RESET} %s\n" "$1" >&2; }

usage() {
    cat <<'EOF'
Usage: ./install.sh [options] [skill ...]

Options:
  --all             Process all skills without showing the menus
  --target LIST     Comma-separated targets: copilot, claude, agents
                    (default: all targets)
  --list            Show skills and their status, then exit
  --uninstall       Remove skills instead of installing them
  -h, --help        Show this help

With no skill names or --all, an interactive menu is shown.
EOF
}

contains() {
    local needle="$1" item
    shift
    for item in "$@"; do
        [[ "${item}" == "${needle}" ]] && return 0
    done
    return 1
}

uninstall=false
all=false
list_only=false
requested=()
requested_targets=()
add_targets() {
    local t
    for t in $(printf '%s' "$1" | tr ',' ' '); do
        if ! contains "${t}" "${TARGET_IDS[@]}"; then
            error "Unknown target: ${t}. Available: ${TARGET_IDS[*]}"
            exit 1
        fi
        requested_targets+=("${t}")
    done
}
while [[ $# -gt 0 ]]; do
    case "$1" in
        --uninstall) uninstall=true ;;
        --all)       all=true ;;
        --list)      list_only=true ;;
        --target)
            [[ $# -ge 2 ]] || { error "--target requires a value"; exit 1; }
            add_targets "$2"; shift ;;
        --target=*)  add_targets "${1#--target=}" ;;
        -h|--help)   usage; exit 0 ;;
        -*)          error "Unknown option: $1"; usage; exit 1 ;;
        *)           requested+=("$1") ;;
    esac
    shift
done

if [[ ! -d "${SKILLS_SRC}" ]]; then
    error "Skills directory not found: ${SKILLS_SRC}"
    exit 1
fi

# Discover all skills (directories containing SKILL.md)
skills=()
for skill_md in "${SKILLS_SRC}"/*/SKILL.md; do
    [[ -f "${skill_md}" ]] || continue
    skills+=("$(basename "$(dirname "${skill_md}")")")
done

if [[ ${#skills[@]} -eq 0 ]]; then
    warn "No skills found in ${SKILLS_SRC}"
    exit 0
fi

# Prints the metadata version from SKILL.md frontmatter, or nothing.
skill_version() {
    local file="$1/SKILL.md"
    [[ -f "${file}" ]] || return 0
    awk '
        NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; next }
        /^---[[:space:]]*$/ { exit }
        /^[[:space:]]*version:/ {
            sub(/^[[:space:]]*version:[[:space:]]*/, "")
            gsub(/["'\''[:space:]]/, "")
            print
            exit
        }
    ' "${file}"
}

# Compares semantic versions. Prints -1, 0, or 1, or nothing if either is
# missing or unparsable.
compare_versions() {
    local re='^v?([0-9]+(\.[0-9]+)*)(-([0-9A-Za-z.-]+))?(\+.*)?$'
    local a="$1" b="$2" a_core a_pre b_core b_pre i n x y
    [[ -n "${a}" && -n "${b}" ]] || return 0
    [[ "${a}" =~ ${re} ]] || return 0
    a_core="${BASH_REMATCH[1]}"; a_pre="${BASH_REMATCH[4]}"
    [[ "${b}" =~ ${re} ]] || return 0
    b_core="${BASH_REMATCH[1]}"; b_pre="${BASH_REMATCH[4]}"
    local IFS=.
    local -a ap=(${a_core}) bp=(${b_core})
    n=${#ap[@]}
    [[ ${#bp[@]} -gt ${n} ]] && n=${#bp[@]}
    for ((i = 0; i < n; i++)); do
        x=$((10#${ap[$i]:-0})); y=$((10#${bp[$i]:-0}))
        if ((x > y)); then echo 1; return 0; fi
        if ((x < y)); then echo -1; return 0; fi
    done
    # A pre-release (1.0.0-beta) sorts before its release (1.0.0).
    if [[ -n "${a_pre}" && -z "${b_pre}" ]]; then echo -1; return 0; fi
    if [[ -z "${a_pre}" && -n "${b_pre}" ]]; then echo 1; return 0; fi
    if [[ "${a_pre}" < "${b_pre}" ]]; then echo -1
    elif [[ "${a_pre}" > "${b_pre}" ]]; then echo 1
    else echo 0
    fi
}

# Parallel arrays (bash 3.2 compatible) describing each skill's status.
# Kinds: not-installed, up-to-date, update, modified, newer, partial
# target_states is flattened: index = skill_index * target_count + target_index,
# with values missing, current, or differs.
n_targets=${#TARGETS[@]}
available_versions=()
kinds=()
statuses=()
installed_versions=()
installed_counts=()
target_states=()
for skill in "${skills[@]}"; do
    src="${SKILLS_SRC}/${skill}"
    avail="$(skill_version "${src}")"
    count=0
    differs=false
    inst_ver=""
    for target in "${TARGETS[@]}"; do
        dst="${target}/${skill}"
        if [[ ! -d "${dst}" ]]; then
            target_states+=("missing")
            continue
        fi
        count=$((count + 1))
        if diff -rq "${src}" "${dst}" >/dev/null 2>&1; then
            target_states+=("current")
        else
            target_states+=("differs")
            differs=true
        fi
        # Track the lowest installed version so any outdated target counts.
        v="$(skill_version "${dst}")"
        if [[ -n "${v}" ]] && { [[ -z "${inst_ver}" ]] || [[ "$(compare_versions "${v}" "${inst_ver}")" == "-1" ]]; }; then
            inst_ver="${v}"
        fi
    done
    cmp="$(compare_versions "${avail}" "${inst_ver}")"

    if [[ ${count} -eq 0 ]]; then
        kinds+=("not-installed"); statuses+=("not installed")
    elif ! $differs && [[ ${count} -eq ${n_targets} ]]; then
        kinds+=("up-to-date"); statuses+=("up to date")
    elif [[ "${cmp}" == "1" ]]; then
        kinds+=("update"); statuses+=("update available (${inst_ver} -> ${avail})")
    elif [[ "${cmp}" == "-1" ]]; then
        kinds+=("newer"); statuses+=("installed is newer (${inst_ver} > ${avail})")
    elif $differs && [[ "${cmp}" == "0" ]]; then
        kinds+=("modified"); statuses+=("modified (version not bumped)")
    elif $differs; then
        kinds+=("update"); statuses+=("update available")
    else
        kinds+=("partial"); statuses+=("partially installed (${count}/${n_targets} targets)")
    fi
    if [[ ${count} -gt 0 && -z "${inst_ver}" ]]; then inst_ver="yes"; fi
    available_versions+=("${avail:--}")
    installed_versions+=("${inst_ver:--}")
    installed_counts+=("${count}")
done

kind_color() {
    case "$1" in
        up-to-date)     printf '%s' "${GREEN}" ;;
        update|partial) printf '%s' "${YELLOW}" ;;
        modified)       printf '%s' "${MAGENTA}" ;;
        newer)          printf '%s' "${CYAN}" ;;
        *)              printf '%s' "" ;;
    esac
}

show_table() {
    local width=5 i skill
    for skill in "${skills[@]}"; do
        [[ ${#skill} -gt ${width} ]] && width=${#skill}
    done
    printf "${DIM}  %3s  %-${width}s  %-10s  %-10s  %s${RESET}\n" "#" "Skill" "Available" "Installed" "Status"
    for i in "${!skills[@]}"; do
        printf "$(kind_color "${kinds[$i]}")  %3s  %-${width}s  %-10s  %-10s  %s${RESET}\n" \
            "$((i + 1))" "${skills[$i]}" "${available_versions[$i]}" "${installed_versions[$i]}" "${statuses[$i]}"
    done
    echo
}

format_path() {
    case "$1" in
        "${HOME}"/*) printf '~%s' "${1#"${HOME}"}" ;;
        *)           printf '%s' "$1" ;;
    esac
}

# Prints a normalized key: up, down, space, enter, esc, or a lowercase character.
read_key() {
    local k="" rest="" timeout=1
    [[ ${BASH_VERSINFO[0]} -ge 4 ]] && timeout=0.1
    IFS= read -rsn1 k || { echo esc; return 0; }
    case "${k}" in
        $'\x1b')
            IFS= read -rsn2 -t "${timeout}" rest || true
            case "${rest}" in
                '[A'|'OA') echo up ;;
                '[B'|'OB') echo down ;;
                *)         echo esc ;;
            esac
            ;;
        '')  echo enter ;;
        ' ') echo space ;;
        *)   printf '%s\n' "${k}" | tr '[:upper:]' '[:lower:]' ;;
    esac
}

# Interactive checkbox list. Uses the menu_labels, menu_details, menu_colors,
# and menu_checked (0/1) arrays. Sets menu_result to the selected indices.
# Returns 1 when cancelled.
checkbox_menu() {
    local title="$1" count=${#menu_labels[@]} cursor=0 msg="" drawn=false
    local width=0 i key pointer box row_color all_on
    for i in "${!menu_labels[@]}"; do
        [[ ${#menu_labels[$i]} -gt ${width} ]] && width=${#menu_labels[$i]}
    done
    menu_result=()

    printf "  ${BOLD}%s${RESET}\n" "${title}"
    printf '\033[?25l'
    while true; do
        $drawn && printf '\033[%dA' $((count + 2))
        drawn=true
        for ((i = 0; i < count; i++)); do
            pointer=" "; row_color=""
            if [[ ${i} -eq ${cursor} ]]; then pointer=">"; row_color="${CYAN}"; fi
            box="[ ]"; [[ ${menu_checked[$i]} -eq 1 ]] && box="[x]"
            printf "\033[2K${row_color}  %s %s %-${width}s${RESET}  ${menu_colors[$i]}%s${RESET}\n" \
                "${pointer}" "${box}" "${menu_labels[$i]}" "${menu_details[$i]}"
        done
        printf "\033[2K${DIM}  up/down move, space toggle, a all, enter confirm, q cancel${RESET}\n"
        printf "\033[2K${YELLOW}  %s${RESET}\n" "${msg}"
        msg=""

        key="$(read_key)"
        case "${key}" in
            up|k)   cursor=$(( (cursor - 1 + count) % count )) ;;
            down|j) cursor=$(( (cursor + 1) % count )) ;;
            space)  menu_checked[$cursor]=$(( 1 - menu_checked[$cursor] )) ;;
            a)
                all_on=0
                for ((i = 0; i < count; i++)); do
                    [[ ${menu_checked[$i]} -eq 0 ]] && all_on=1
                done
                for ((i = 0; i < count; i++)); do menu_checked[$i]=${all_on}; done
                ;;
            enter)
                for ((i = 0; i < count; i++)); do
                    [[ ${menu_checked[$i]} -eq 1 ]] && menu_result+=("${i}")
                done
                if [[ ${#menu_result[@]} -gt 0 ]]; then
                    printf '\033[?25h\n'
                    return 0
                fi
                msg="Select at least one item, or press q to cancel."
                ;;
            esc|q)
                printf '\033[?25h\n'
                return 1
                ;;
        esac
    done
}

# Prints what would change in target index $1 for the selected skill indices.
target_detail() {
    local ti=$1 si state new=0 upd=0 cur=0 note=""
    shift
    for si in "$@"; do
        state="${target_states[$((si * n_targets + ti))]}"
        case "${state}" in
            missing) new=$((new + 1)) ;;
            differs) upd=$((upd + 1)) ;;
            current) cur=$((cur + 1)) ;;
        esac
    done
    if $uninstall; then
        if [[ $((upd + cur)) -gt 0 ]]; then note="$((upd + cur)) to remove"; else note="nothing to remove"; fi
    else
        [[ ${new} -gt 0 ]] && note="${new} new"
        [[ ${upd} -gt 0 ]] && note="${note:+${note}, }${upd} update"
        [[ ${cur} -gt 0 ]] && note="${note:+${note}, }${cur} current"
    fi
    printf '%s  (%s)' "$(format_path "${TARGETS[$ti]}")" "${note}"
}

printf "\n${BOLD}Kafkade Agent Skills${RESET}\n\n"

if $list_only; then
    show_table
    exit 0
fi

selected=()
selected_targets=()
if [[ ${#requested[@]} -eq 0 ]] && ! $all && [[ -t 0 ]]; then
    trap 'printf "\033[?25h"' EXIT
    trap 'exit 130' INT

    # Step 1: skills
    menu_rows=()
    for i in "${!skills[@]}"; do
        if ! $uninstall || [[ ${installed_counts[$i]} -gt 0 ]]; then
            menu_rows+=("${i}")
        fi
    done
    if [[ ${#menu_rows[@]} -eq 0 ]]; then
        warn "No skills are installed."
        exit 0
    fi
    menu_labels=(); menu_details=(); menu_colors=(); menu_checked=()
    for i in "${menu_rows[@]}"; do
        menu_labels+=("${skills[$i]}")
        menu_details+=("$(printf '%-10s  %s' "${available_versions[$i]}" "${statuses[$i]}")")
        menu_colors+=("$(kind_color "${kinds[$i]}")")
        # Preselect new and outdated skills; never preselect a downgrade.
        case "${kinds[$i]}" in
            up-to-date|newer) menu_checked+=(0) ;;
            *) if $uninstall; then menu_checked+=(0); else menu_checked+=(1); fi ;;
        esac
    done
    if $uninstall; then title="Select skills to uninstall"; else title="Select skills to install or update"; fi
    if ! checkbox_menu "${title}"; then echo "Cancelled."; exit 0; fi
    selected_idx=()
    for i in "${menu_result[@]}"; do
        selected_idx+=("${menu_rows[$i]}")
        selected+=("${skills[${menu_rows[$i]}]}")
    done

    # Step 2: targets
    menu_labels=(); menu_details=(); menu_colors=(); menu_checked=()
    for ti in "${!TARGETS[@]}"; do
        menu_labels+=("${TARGET_LABELS[$ti]}")
        menu_details+=("$(target_detail "${ti}" "${selected_idx[@]}")")
        menu_colors+=("${DIM}")
        if $uninstall; then
            on=0
            for si in "${selected_idx[@]}"; do
                [[ "${target_states[$((si * n_targets + ti))]}" != "missing" ]] && on=1
            done
            menu_checked+=("${on}")
        else
            menu_checked+=(1)
        fi
    done
    if $uninstall; then title="Select targets to remove from"; else title="Select targets to install to"; fi
    if ! checkbox_menu "${title}"; then echo "Cancelled."; exit 0; fi
    target_names=()
    for ti in "${menu_result[@]}"; do
        selected_targets+=("${ti}")
        target_names+=("${TARGET_LABELS[$ti]}")
    done

    # Step 3: confirm
    if $uninstall; then action="Uninstall"; else action="Install"; fi
    joined_skills="$(printf ', %s' "${selected[@]}")"
    joined_targets="$(printf ', %s' "${target_names[@]}")"
    printf "${DIM}  %s skills:${RESET} %s\n" "${action}" "${joined_skills:2}"
    printf "${DIM}  Targets:${RESET} %s\n\n" "${joined_targets:2}"
    printf "  Proceed? [Y/n] "
    answer="$(read_key)"
    echo
    case "${answer}" in
        enter|y) ;;
        *) echo "Cancelled."; exit 0 ;;
    esac
    echo
else
    if [[ ${#requested[@]} -gt 0 ]]; then
        for skill in "${requested[@]}"; do
            if ! contains "${skill}" "${skills[@]}"; then
                error "Unknown skill: ${skill}. Available: ${skills[*]}"
                exit 1
            fi
            if [[ ${#selected[@]} -eq 0 ]] || ! contains "${skill}" "${selected[@]}"; then
                selected+=("${skill}")
            fi
        done
    else
        selected=("${skills[@]}")
    fi
    for ti in "${!TARGETS[@]}"; do
        if [[ ${#requested_targets[@]} -eq 0 ]] || contains "${TARGET_IDS[$ti]}" "${requested_targets[@]}"; then
            selected_targets+=("${ti}")
        fi
    done
fi

for ti in "${selected_targets[@]}"; do
    target="${TARGETS[$ti]}"
    printf "${DIM}→ %s: %s${RESET}\n" "${TARGET_LABELS[$ti]}" "${target}"

    if $uninstall; then
        for skill in "${selected[@]}"; do
            if [[ -d "${target}/${skill}" ]]; then
                rm -rf "${target}/${skill}"
                info "Removed ${skill}"
            else
                warn "Not installed: ${skill}"
            fi
        done
    else
        mkdir -p "${target}"
        for skill in "${selected[@]}"; do
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
    printf "${BOLD}%d skill(s)${RESET} removed from %d target(s).\n" "${#selected[@]}" "${#selected_targets[@]}"
else
    printf "${BOLD}%d skill(s)${RESET} installed to %d target(s).\n" "${#selected[@]}" "${#selected_targets[@]}"
fi
printf "Restart your agent or run ${BOLD}/skills reload${RESET} to apply.\n"
