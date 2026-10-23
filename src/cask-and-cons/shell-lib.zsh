# =============================================================================
# Shared shell library — cask-and-cons (zsh)
# Mirrors heks-bash/src/heks-bash/shell-lib.bash and the inline copy in
# wolk-jjba/home/bash/bashrc.sh: same layout, same colours, same helpers, so
# all three machines feel like one system.
#
# Everything machine-specific comes from the CC_* variables the host config
# sets *before* calling `cc_boot':
#
#   CC_FLAVOR     name of the config, e.g. cask-and-cons
#   CC_HOST_KIND  at-a-glance machine kind, e.g. macos
#   CC_SIGIL      prompt sigil, e.g. ⌘
#   CC_ACCENT     256-colour accent (0-255), e.g. 175
#   CC_RC_FILE    file `reload' sources
#   CC_PATH_DEPTH path components kept in the prompt (default 3)
#
# No prompt framework, no plugins: one `git status --porcelain=v2 --branch' is
# the only fork behind each prompt. The pager is plain less with the Emacs
# keymap from the sibling `lesskey' file, installed by the same installer that
# writes this rc.
# =============================================================================

CC_PATH_DEPTH=${CC_PATH_DEPTH:-3}
CC_ACCENT=${CC_ACCENT:-99}
: "${CC_FLAVOR:=shell}"
: "${CC_HOST_KIND:=unix}"
: "${CC_SIGIL:=λ}"
: "${CC_RC_FILE:=$HOME/.zshrc}"

# ---- history ----------------------------------------------------------------
# The setopts that matter (SHARE_HISTORY, INC_APPEND_HISTORY, EXTENDED_HISTORY,
# HIST_IGNORE_*) are declared in zsh.scm; these are the plain values.
HISTFILE=${HISTFILE:-$HOME/.zsh_history}
HISTSIZE=${HISTSIZE:-500000}
SAVEHIST=${SAVEHIST:-100000}

# ---- pager ------------------------------------------------------------------
# One pager everywhere (less), with Emacs key bindings: the keymap is the
# shared lesskey source file installed as $XDG_CONFIG_HOME/lesskey — less 582
# and later read it directly, so there is no compiled file to keep in sync.
# -F quit-if-one-screen, -I case-insensitive search, -M long prompt, -R colour.
export PAGER=${PAGER:-less}
export MANPAGER=${MANPAGER:-less}
export LESS="-F -I -M -R"
# less looks for that file on its own, so nothing needs to be exported; older
# less versions (< 582) simply ignore it and keep their default keys.
CC_LESSKEY=${XDG_CONFIG_HOME:-$HOME/.config}/lesskey
export CC_LESSKEY

# ---- palette ----------------------------------------------------------------
# 256-colour ANSI, wrapped in %{...%} so zsh does not count them as width.
# `CC_PLAIN=1' (or NO_COLOR / TERM=dumb) renders the same prompt without colour.
__cc_palette () {
    local v name
    if [[ ${CC_PLAIN:-0} != 0 || -n ${NO_COLOR:-} || ${TERM:-dumb} == dumb ]]
    then
        for v in ACCENT TEXT DIM PATH BRANCH DIRTY AB BAD GOOD BOLD RESET
        do
            printf -v "CC_${v}_SEQ" '%s' ''
            printf -v "CC_${v}_OUT" '%s' ''
        done
        return 0
    fi
    # plain escapes: used by normal output (greeting, about)
    printf -v CC_RESET_OUT '\033[0m'
    printf -v CC_BOLD_OUT '\033[1m'
    printf -v CC_ACCENT_OUT '\033[38;5;%sm' "$CC_ACCENT"
    printf -v CC_TEXT_OUT '\033[38;5;252m'
    printf -v CC_DIM_OUT '\033[38;5;244m'
    printf -v CC_PATH_OUT '\033[38;5;111m'
    printf -v CC_BRANCH_OUT '\033[38;5;81m'
    printf -v CC_DIRTY_OUT '\033[38;5;221m'
    printf -v CC_AB_OUT '\033[38;5;176m'
    printf -v CC_BAD_OUT '\033[38;5;203m'
    printf -v CC_GOOD_OUT '\033[38;5;114m'
    # prompt copies: %{...%} tells zsh these escapes have zero width
    for v in ACCENT TEXT DIM PATH BRANCH DIRTY AB BAD GOOD BOLD RESET
    do
        name=CC_${v}_OUT
        printf -v "CC_${v}_SEQ" '%%{%s%%}' "${(P)name}"
    done
}

# ---- prompt pieces ----------------------------------------------------------
# $HOME becomes ~, then only the last CC_PATH_DEPTH components are kept.
__cc_trim_path () {
    local p=${PWD/#$HOME/\~} depth=$CC_PATH_DEPTH
    local -a parts
    parts=("${(@s:/:)p}")
    local n=$#parts
    ((n <= depth)) && { print -r -- "$p"; return 0; }
    print -r -- "…/${(j:/:)parts[n - depth + 1, n]}"
}

# Environment badges: Guix shell, Nix shell, Python venv.
__cc_env_badge () {
    if [[ -n ${GUIX_ENVIRONMENT:-} ]]
    then
        print -rn -- " ${CC_DIM_SEQ}[guix env]${CC_RESET_SEQ}"
    elif [[ -n ${IN_NIX_SHELL:-} ]]
    then
        print -rn -- " ${CC_DIM_SEQ}[nix]${CC_RESET_SEQ}"
    elif [[ -n ${VIRTUAL_ENV:-} ]]
    then
        print -rn -- " ${CC_DIM_SEQ}[venv]${CC_RESET_SEQ}"
    fi
}

# One fork per prompt: porcelain v2 gives branch, upstream divergence and the
# dirty state in a single call. Untracked files are ignored (they are noise).
__cc_git_sync () {
    CC_GIT_SEG=''
    local dir=$PWD gd=''
    while :
    do
        if [[ -e $dir/.git ]]
        then
            gd=$dir
            break
        fi
        [[ $dir == / ]] && return 0
        dir=${dir%/*}
        [[ -z $dir ]] && dir=/
    done
    local out
    out=$(GIT_OPTIONAL_LOCKS=0 git -C "$gd" status --porcelain=v2 --branch \
        --ignore-submodules=dirty --untracked-files=no 2> /dev/null) || return 0
    local branch='' oid='' ahead=0 behind=0 changed=0 conflicts=0 stash=0
    local line ab
    while IFS= read -r line
    do
        case $line in
            '# branch.head '*)
                branch=${line#'# branch.head '}
                ;;
            '# branch.oid '*)
                oid=${line#'# branch.oid '}
                ;;
            '# branch.ab '*)
                ab=${line#'# branch.ab '}
                ahead=${ab%% *}
                ahead=${ahead#+}
                behind=${ab##* }
                behind=${behind#-}
                ;;
            'u '*)
                conflicts=$((conflicts + 1))
                ;;
            [12]' '*)
                changed=$((changed + 1))
                ;;
        esac
    done <<< "$out"
    [[ -z $branch ]] && return 0
    [[ $branch == '(detached)' ]] && branch=@${oid:0:7}
    branch=${branch//\%/%%}   # % is a prompt escape in zsh
    # Stash entries are small plain-text logs; counting them costs no fork.
    if [[ -f $gd/.git/logs/refs/stash ]]
    then
        while read -r _
        do
            stash=$((stash + 1))
        done < "$gd/.git/logs/refs/stash"
    fi
    CC_GIT_SEG=" ${CC_BRANCH_SEQ}${branch}${CC_RESET_SEQ}"
    if ((conflicts))
    then
        CC_GIT_SEG+=" ${CC_BAD_SEQ}✖${conflicts}${CC_RESET_SEQ}"
    elif ((changed))
    then
        CC_GIT_SEG+=" ${CC_DIRTY_SEQ}✚${changed}${CC_RESET_SEQ}"
    else
        CC_GIT_SEG+=" ${CC_GOOD_SEQ}✓${CC_RESET_SEQ}"
    fi
    ((ahead)) && CC_GIT_SEG+=" ${CC_AB_SEQ}↑${ahead}${CC_RESET_SEQ}"
    ((behind)) && CC_GIT_SEG+=" ${CC_AB_SEQ}↓${behind}${CC_RESET_SEQ}"
    ((stash)) && CC_GIT_SEG+=" ${CC_DIM_SEQ}⚑${stash}${CC_RESET_SEQ}"
    return 0
}

# Two lines everywhere, identical on every machine:
#   ╭─ user@host <sigil> <kind>  ~/some/where [guix env]
#   ╰─ main ✚2 ↑1  <sigil>
__cc_prompt () {
    local cwd badge
    cwd=$(__cc_trim_path)
    cwd=${cwd//\%/%%}   # % is a prompt escape in zsh
    badge=$(__cc_env_badge)
    __cc_git_sync
    PS1="${CC_DIM_SEQ}╭─ ${CC_RESET_SEQ}${CC_BOLD_SEQ}%n${CC_RESET_SEQ}"
    PS1+="${CC_DIM_SEQ}@${CC_RESET_SEQ}%m "
    PS1+="${CC_ACCENT_SEQ}${CC_SIGIL} ${CC_HOST_KIND}${CC_RESET_SEQ} "
    PS1+="${CC_PATH_SEQ}${cwd}${CC_RESET_SEQ}${badge}"$'\n'
    PS1+="${CC_DIM_SEQ}╰─${CC_RESET_SEQ}${CC_GIT_SEG} "
    PS1+="${CC_ACCENT_SEQ}${CC_SIGIL}${CC_RESET_SEQ} "
    return 0
}

# ---- greeting ---------------------------------------------------------------
# The pool of sayings (CC_GREETINGS) is data and lives in zsh.scm
# (`zsh-greetings'); it is emitted into the rc before this runs.

shell-greeting () {
    local q=${CC_GREETINGS[$((RANDOM % $#CC_GREETINGS + 1))]}
    printf '%s%s%s %s%s%s  %s%s%s\n\n' \
        "$CC_ACCENT_OUT" "$CC_SIGIL" "$CC_RESET_OUT" \
        "$CC_BOLD_OUT" "$CC_FLAVOR" "$CC_RESET_OUT" \
        "$CC_DIM_OUT" "$q" "$CC_RESET_OUT"
}

# ---- self knowledge ---------------------------------------------------------
about () {
    local shell_name="zsh $ZSH_VERSION"
    printf '%s%s%s %s%s%s\n' \
        "$CC_ACCENT_OUT" "$CC_SIGIL" "$CC_RESET_OUT" \
        "$CC_BOLD_OUT" "$CC_FLAVOR" "$CC_RESET_OUT"
    printf '  %skind%s    %s\n' "$CC_DIM_OUT" "$CC_RESET_OUT" "$CC_HOST_KIND"
    printf '  %shost%s    %s@%s\n' "$CC_DIM_OUT" "$CC_RESET_OUT" "${USER:-$(id -un)}" "$(uname -n)"
    printf '  %ssystem%s  %s\n' "$CC_DIM_OUT" "$CC_RESET_OUT" "$(uname -srm)"
    printf '  %sshell%s   %s\n' "$CC_DIM_OUT" "$CC_RESET_OUT" "$shell_name"
    printf '  %sconfig%s  %s\n' "$CC_DIM_OUT" "$CC_RESET_OUT" "$CC_RC_FILE"
    printf '  %sgit%s     %s\n' "$CC_DIM_OUT" "$CC_RESET_OUT" "$(git --version 2> /dev/null | cut -d' ' -f3)"
    printf '  %sprompt%s  accent %s · sigil %s · depth %s · %s\n' \
        "$CC_DIM_OUT" "$CC_RESET_OUT" "$CC_ACCENT" "$CC_SIGIL" "$CC_PATH_DEPTH" \
        "$([[ ${CC_PLAIN:-0} != 0 || -n ${NO_COLOR:-} ]] && echo plain || echo colour)"
    printf '  %spager%s   less · Emacs keys · %s\n' \
        "$CC_DIM_OUT" "$CC_RESET_OUT" "$CC_LESSKEY"
    printf '  %shelpers%s about · pager-keys · hist-top · paths · extract · mkcd · up · serve · bak · calc · json · notify\n' \
        "$CC_DIM_OUT" "$CC_RESET_OUT"
}

# -----------------------------------------------------------------------------
# Helper functions (vanilla: coreutils + git only)
# -----------------------------------------------------------------------------
__cc_has () { command -v "$1" > /dev/null 2>&1; }

mkcd () {
    if [[ -z ${1:-} ]]
    then
        printf 'usage: mkcd <dir>\n' >&2
        return 2
    fi
    mkdir -p -- "$1" && cd -- "$1"
}

up () {
    local n=${1:-1} p=''
    while ((n-- > 0))
    do
        p+=../
    done
    cd "$p" || return
    pwd
}

extract () {
    local f=${1:-}
    if [[ ! -f $f ]]
    then
        printf 'extract: not a file: %s\n' "${f:-<none>}" >&2
        return 1
    fi
    case $f in
        *.tar.bz2 | *.tbz2) tar xjf "$f" ;;
        *.tar.gz | *.tgz) tar xzf "$f" ;;
        *.tar.xz | *.txz) tar xJf "$f" ;;
        *.tar.zst) tar --zstd -xf "$f" ;;
        *.tar) tar xf "$f" ;;
        *.zip) unzip -q "$f" ;;
        *.7z) 7z x "$f" ;;
        *.rar) unrar x "$f" ;;
        *.gz) gzip -dc "$f" > "${f%.gz}" ;;
        *.bz2) bzip2 -dc "$f" > "${f%.bz2}" ;;
        *.xz) xz -dc "$f" > "${f%.xz}" ;;
        *.zst) zstd -dc "$f" > "${f%.zst}" ;;
        *)
            printf 'extract: unknown archive type: %s\n' "$f" >&2
            return 1
            ;;
    esac
}

psg () {
    if [[ -z ${1:-} ]]
    then
        printf 'usage: psg <pattern>\n' >&2
        return 2
    fi
    ps aux | grep -i -- "[${1:0:1}]${1:1}"
}

kport () {
    local p=${1:-} pids=''
    if [[ -z $p ]]
    then
        printf 'usage: kport <port>\n' >&2
        return 2
    fi
    if __cc_has lsof
    then
        pids=$(lsof -ti "tcp:$p" 2> /dev/null)
    elif __cc_has ss
    then
        pids=$(ss -tlnpH "sport = :$p" 2> /dev/null \
            | grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -u)
    fi
    if [[ -z $pids ]]
    then
        printf 'kport: nothing listening on %s\n' "$p" >&2
        return 1
    fi
    kill $pids && printf 'kport: sent TERM to %s\n' "$pids"
}

serve () {
    local p=${1:-8000}
    printf 'serving %s on http://localhost:%s\n' "$PWD" "$p"
    if __cc_has python3
    then
        python3 -m http.server "$p"
    else
        python -m SimpleHTTPServer "$p"
    fi
}

# Desktop notification: notify-send where available, otherwise the terminal
# bell on the controlling TTY (so it is harmless in scripts and over SSH).
notify () {
    local msg=${1:-done} title=${2:-$(hostname -s)}
    if __cc_has notify-send
    then
        notify-send "$title" "$msg"
    elif [[ -t 1 ]]
    then
        printf '\a%s: %s\n' "$title" "$msg"
    else
        printf '%s: %s\n' "$title" "$msg"
    fi
}

# Listening sockets: ss on Linux, lsof on macOS/BSD.
ports () {
    if __cc_has ss
    then
        ss -tulpn
    else
        lsof -iTCP -sTCP:LISTEN -P -n
    fi
}

bak () {
    local f=${1:-}
    if [[ -z $f ]]
    then
        printf 'usage: bak <file>\n' >&2
        return 2
    fi
    local d
    d=$f.$(date +%Y%m%d-%H%M%S).bak
    cp -p -- "$f" "$d" && printf '→ %s\n' "$d"
}

calc () {
    if (($# == 0))
    then
        printf 'usage: calc <expression>\n' >&2
        return 2
    fi
    LC_ALL=C awk "BEGIN { printf \"%.10g\\n\", $* }"
}

json () {
    if __cc_has python3
    then
        python3 -m json.tool "$@"
    else
        cat "$@"
    fi
}

paths () {
    local -a entries=("${(@s.:.)PATH}")
    local i=0 p
    for p in $entries
    do
        printf '%2d  %s\n' "$i" "$p"
        i=$((i + 1))
    done
}

# The pager keymap (installed as $XDG_CONFIG_HOME/lesskey) in one screen.
pager-keys () {
    local b=${CC_BOLD_OUT:-} d=${CC_DIM_OUT:-} r=${CC_RESET_OUT:-}
    local a=${CC_ACCENT_OUT:-}
    printf '%s%spager%s less · Emacs keys · %s\n\n' \
        "$b" "$a" "$r$d" "$CC_LESSKEY"
    printf '  %s%-11s%s %s\n' "$b" 'C-n  C-p' "$r" 'one line down / up'
    printf '  %s%-11s%s %s\n' "$b" 'C-f  C-b' "$r" 'one screen down / up'
    printf '  %s%-11s%s %s\n' "$b" 'C-v  M-v' "$r" 'one screen down / up'
    printf '  %s%-11s%s %s\n' "$b" 'C-d  C-u' "$r" 'half a screen down / up'
    printf '  %s%-11s%s %s\n' "$b" 'C-a  C-e' "$r" 'top / bottom of the file'
    printf '  %s%-11s%s %s\n' "$b" 'M-<  M->' "$r" 'top / bottom of the file'
    printf '  %s%-11s%s %s\n' "$b" 'C-s  C-r' "$r" 'search forward / backward'
    printf '  %s%-11s%s %s\n' "$b" 'M-g' "$r" 'go to line'
    printf '  %s%-11s%s %s\n' "$b" 'M-u' "$r" 'clear the search highlighting'
    printf '  %s%-11s%s %s\n' "$b" 'C-l' "$r" 'redraw the screen'
    printf '\n  %sin prompts (:e, /, ?, ...)%s\n' "$d" "$r"
    printf '  %s%-11s%s %s\n' "$b" 'C-a  C-e' "$r" 'beginning / end of the line'
    printf '  %s%-11s%s %s\n' "$b" 'C-b  C-f' "$r" 'one character left / right'
    printf '  %s%-11s%s %s\n' "$b" 'M-b  M-f' "$r" 'one word left / right'
    printf '  %s%-11s%s %s\n' "$b" 'C-w  M-d' "$r" 'kill the word before / after the cursor'
    printf '  %s%-11s%s %s\n' "$b" 'C-k  C-u' "$r" 'kill the whole line'
    printf '  %s%-11s%s %s\n' "$b" 'C-g' "$r" 'cancel the prompt'
    printf '\n  %sstill plain less%s: space b · g G · / ? · n N · m '\'' · ! · | · q%s\n' \
        "$d" "$r" "$r"
}

reload () {
    printf 'reloading %s\n' "$CC_RC_FILE"
    CC_RELOAD=1 . "$CC_RC_FILE"
}

cdroot () {
    local d=$PWD
    while :
    do
        if [[ -e $d/.git ]]
        then
            cd "$d" || return 1
            return 0
        fi
        [[ $d == / ]] && break
        d=${d%/*}
        [[ -z $d ]] && d=/
    done
    printf 'cdroot: not inside a git work tree\n' >&2
    return 1
}

ff () {
    if [[ -z ${1:-} ]]
    then
        printf 'usage: ff <name-fragment>\n' >&2
        return 2
    fi
    find . -iname "*${1}*" -not -path './.git/*' -not -path './node_modules/*'
}

# Most frequently used commands, straight from the history file.
hist-top () {
    local n=${1:-10} f=${HISTFILE:-$HOME/.zsh_history}
    [[ -r $f ]] || return 0
    sed -e 's/^: [0-9]*:[0-9]*;//' "$f" | awk 'NF { print $1 }' \
        | sort | uniq -c | sort -rn | head -n "$n"
}

hgrep () {
    fc -l 1 | grep -- "${1:-}"
}

# Decompress a .gz log and page through it.
gunlog () {
    if [[ -z ${1:-} ]]
    then
        printf 'usage: gunlog <file.gz>\n' >&2
        return 2
    fi
    gzip -dc -- "$1" | ${PAGER:-less}
}

# Startup cost of the shell itself, averaged over a few runs.
rc-time () {
    local n=${1:-5} t0 t1 i
    zmodload zsh/datetime 2> /dev/null
    t0=${EPOCHREALTIME//,/.}   # EPOCHREALTIME honours LC_NUMERIC
    for ((i = 0; i < n; i++))
    do
        zsh -i -c exit > /dev/null 2>&1
    done
    t1=${EPOCHREALTIME//,/.}
    if [[ -z $t0 || -z $t1 ]]
    then
        printf 'rc-time: needs the zsh/datetime module\n' >&2
        return 1
    fi
    LC_ALL=C awk -v a="$t0" -v b="$t1" -v n="$n" \
        'BEGIN { printf "%.1f ms per start (%d runs)\n", (b - a) * 1000 / n, n }'
}

# ---- git -------------------------------------------------------------------
# The one-line git shortcuts (gst, gd, gco, ...) are generated from
# `zsh-git-shortcuts' in zsh.scm; only the multi-line ones stay here.

glog () {
    local n=${1:-20}
    git log --graph --abbrev-commit --decorate --date=short \
        --format='%C(auto)%h%C(reset) %C(auto)%d%C(reset) %s %C(dim)(%ar)%C(reset)' \
        -n "$n" --all
}


# caco: available everywhere; navigates to the repo, then runs the task.
caco () {
    cd ~/Hacking/cask-and-cons || return
    ./caco "$@"
}


# -----------------------------------------------------------------------------
# Boot: colours, prompt hook, greeting. Called once at the end of the rc file.
# -----------------------------------------------------------------------------
cc_boot () {
    __cc_palette
    # No XOFF/XON: C-s is forward-search in zle and in the pager, not a frozen
    # terminal. Set per TTY, and only when there is one.
    [[ -t 0 ]] && stty -ixon 2> /dev/null
    autoload -Uz add-zsh-hook
    (( ${precmd_functions[(I)__cc_prompt]} )) \
        || add-zsh-hook precmd __cc_prompt
    __cc_prompt
    [[ ${CC_RELOAD:-0} == 1 ]] || shell-greeting
    return 0
}
