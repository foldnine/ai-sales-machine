#!/usr/bin/env bash
#
# AI Sales Machine - one-line install.
#
#   curl -fsSL https://raw.githubusercontent.com/foldnine/ai-sales-machine/main/get.sh | bash
#
# Clones the repository (or updates an existing clone) and runs ./install.sh,
# which asks a few questions and sets everything up. Nothing that sends email
# is switched on. Read this script before you pipe it into a shell; it is
# short on purpose.
#
# Options go after "bash -s --" and are passed to install.sh:
#
#   curl -fsSL .../get.sh | bash -s -- --skip-models
#
# Environment:
#   AISALES_DIR   where to put the checkout   (default: ~/ai-sales-machine)
#   AISALES_REF   branch or tag to install    (default: main)
#   AISALES_REPO  repository to clone         (default: the upstream on GitHub)
#
# Written for bash 3.2 (macOS) as well as Linux.

# Everything lives in main(), called on the last line, so a download cut off
# halfway runs nothing at all.
main() {
    set -euo pipefail

    local repo="${AISALES_REPO:-https://github.com/foldnine/ai-sales-machine.git}"
    local ref="${AISALES_REF:-main}"
    local dir="${AISALES_DIR:-$HOME/ai-sales-machine}"

    local B="" R="" RED="" GREEN=""
    if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
        B=$'\033[1m'; R=$'\033[0m'; RED=$'\033[31m'; GREEN=$'\033[32m'
    fi
    say()  { printf '%s==>%s %s\n' "$B" "$R" "$1" >&2; }
    fail() { printf '%s✗ %s%s\n' "$RED" "$1" "$R" >&2; exit 1; }

    # Only what is needed to get the code; install.sh checks the rest
    # (make, openssl, python3, Docker running, Compose v2, Ollama) and says
    # what is missing.
    local c
    for c in git docker; do
        command -v "$c" >/dev/null 2>&1 \
            || fail "$c is not installed. Install it and run this again (see the Requirements in the README)."
    done

    if [ -d "$dir/.git" ]; then
        # An existing clone: update it, but never over local changes or onto
        # another repository.
        local origin
        origin=$(git -C "$dir" remote get-url origin 2>/dev/null || true)
        case "$origin" in
            *foldnine/ai-sales-machine*|"$repo") ;;
            *) fail "$dir is a git checkout of something else ($origin). Set AISALES_DIR to another folder." ;;
        esac
        if [ -n "$(git -C "$dir" status --porcelain --untracked-files=no)" ]; then
            fail "$dir has local changes. Commit or stash them, or run ./install.sh there yourself."
        fi
        say "Updating $dir ($ref)"
        git -C "$dir" fetch --quiet origin "$ref"
        git -C "$dir" checkout --quiet "$ref"
        git -C "$dir" merge --quiet --ff-only FETCH_HEAD \
            || fail "$dir has diverged from $ref. Update it by hand, then run ./install.sh there."
    elif [ -e "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
        fail "$dir exists and is not empty. Set AISALES_DIR to another folder."
    else
        say "Cloning into $dir ($ref)"
        git clone --quiet --branch "$ref" "$repo" "$dir"
    fi

    cd "$dir"
    printf '%s✓%s code in %s\n' "$GREEN" "$R" "$dir" >&2

    # Piped into bash, our stdin is this script, not the keyboard. Give
    # install.sh the terminal so it can ask its questions; with no terminal
    # (CI, a provisioning tool) it runs with defaults and INSTALL_* variables.
    if [ -r /dev/tty ] && (: </dev/tty) 2>/dev/null; then
        exec ./install.sh "$@" </dev/tty
    else
        exec ./install.sh --yes "$@"
    fi
}

main "$@"
