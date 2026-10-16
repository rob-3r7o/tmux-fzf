#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/.envs"
set -e

list_favorite_windows() {
    local -a list_options=(-a)
    local -a regular_windows=()
    local -a favorite_windows=()
    local -a client_args=()
    local current_window=""
    local windows line target details order

    if [[ -n "$TMUX_FZF_WINDOW_FILTER" ]]; then
        list_options=(-f "$TMUX_FZF_WINDOW_FILTER")
    fi

    if [[ -z "$TMUX_FZF_WINDOW_FORMAT" ]]; then
        windows=$(tmux list-windows "${list_options[@]}")
    else
        windows=$(tmux list-windows "${list_options[@]}" -F "#S:#{window_index}: $TMUX_FZF_WINDOW_FORMAT")
    fi

    if [[ -z "$TMUX_FZF_SWITCH_CURRENT" ]]; then
        [[ -n "$TMUX_FZF_CLIENT" ]] && client_args=(-c "$TMUX_FZF_CLIENT")
        current_window=$(tmux display-message -p "${client_args[@]}" '#S:#I')
    fi

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" != *": "* ]]; then
            printf 'Unable to parse tmux window entry: %s\n' "$line" >&2
            return 1
        fi

        target="${line%%: *}"
        [[ "$target" == "$current_window" ]] && continue
        details="${line#"$target: "}"
        order=$(tmux display-message -p -t "$target" '#{@tmux_fzf_favorite_order}')
        if [[ "$order" =~ ^[0-9]+$ ]]; then
            favorite_windows+=("$order"$'\t'"$target: ★ $details")
        else
            regular_windows+=("$line")
        fi
    done <<< "$windows"

    if ((${#regular_windows[@]} > 0)); then
        printf '%s\n' "${regular_windows[@]}"
    fi
    if ((${#favorite_windows[@]} > 0)); then
        printf '%s\n' "${favorite_windows[@]}" |
            sort -t $'\t' -k1,1nr |
            cut -f2-
    fi
    printf '[cancel]\n'
}

update_favorite_windows() {
    local action="$1"
    shift
    local entry target order counter

    for entry in "$@"; do
        [[ "$entry" == "[cancel]" ]] && continue
        if [[ "$entry" != *": "* ]]; then
            printf 'Unable to parse tmux window entry: %s\n' "$entry" >&2
            return 1
        fi

        target="${entry%%: *}"
        order=$(tmux display-message -p -t "$target" '#{@tmux_fzf_favorite_order}')
        if [[ "$action" == "save" ]]; then
            [[ "$order" =~ ^[0-9]+$ ]] && continue
            counter=$(tmux show-option -gqv @tmux_fzf_favorite_order_counter)
            [[ "$counter" =~ ^[0-9]+$ ]] || counter=0
            counter=$((counter + 1))
            tmux set-option -g @tmux_fzf_favorite_order_counter "$counter"
            tmux set-option -w -t "$target" @tmux_fzf_favorite_order "$counter"
        elif [[ -n "$order" ]]; then
            tmux set-option -w -u -t "$target" @tmux_fzf_favorite_order
        fi
    done
}

case "$1" in
    list)
        list_favorite_windows
        ;;
    save|remove)
        action="$1"
        shift
        update_favorite_windows "$action" "$@"
        ;;
    *)
        printf 'Usage: %s {list|save|remove} [window entries...]\n' "$0" >&2
        exit 2
        ;;
esac
