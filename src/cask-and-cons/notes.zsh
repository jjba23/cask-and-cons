# =============================================================================
# Notes from the terminal — cask-and-cons (zsh)
#
# The basics of the Emacs notes setup (heks-emacs, notes.el and friends) for a
# shell, for when Emacs is not at hand.  It reads and writes the same plain
# files, in the same formats, so the two never disagree:
#
#   $NOTES_DIR/<topic>/<slug>.org     one Org file per note, topics are folders
#   $NOTES_DIR/todo.org               the inbox (`* Inbox' with `** TODO' items)
#   $NOTES_DIR/habits.org             TODOs with a `.+1w'-style repeater
#   $NOTES_DIR/contacts.org           contacts, details as properties
#   $NOTES_DIR/bookmarks.org          headings are categories, links bookmarks
#   <topic>/index.org                 generated between BEGIN/END markers
#
# Everything is one command, `n'.  fzf is used for the pickers when it is
# there; without it the prompts are plain.  Only coreutils, sed, awk and grep
# are required (rg is used when present).  Run `n help' for the list.
# =============================================================================

: "${NOTES_DIR:=$HOME/Hacking/private-notes}"

typeset -gA CC_NOTES_ACRONYMS
CC_NOTES_ACRONYMS=(
    ah AH ctms CTMS boms BOMS boap BOAP ikea IKEA vko VKO p4 P4 ai AI sbt sbt
    devops DevOps nix Nix guix Guix sss SSS adr ADR http HTTP apis APIs
)

__n_die () { print -u2 -r -- "n: $*"; return 1 }

__n_check () {
    [[ -d ${NOTES_DIR:-} ]] || { __n_die "no notes directory (NOTES_DIR=${NOTES_DIR:-unset})"; return 1 }
}

__n_slug () {
    emulate -L zsh
    setopt extendedglob
    local s=${(L)1}
    s=${s//[^a-z0-9]##/-}
    s=${s##-##}
    s=${s%%-##}
    print -r -- "${s:-untitled}"
}

# `http-apis' -> `HTTP APIs': the same titles the Emacs index pages carry.
__n_pretty () {
    emulate -L zsh
    local seg=${1#.} w
    local -a out
    for w in ${(s:-:)seg}
    do
        if [[ -n ${CC_NOTES_ACRONYMS[$w]:-} ]]
        then
            out+=${CC_NOTES_ACRONYMS[$w]}
        elif [[ $w == (and|of|for|the|to|in|a|on) ]]
        then
            out+=$w
        else
            out+=${(C)w}
        fi
    done
    print -r -- "${(j: :)out}"
}

__n_title () {
    local t
    t=$(sed -n -e 's/^#+[Tt][Ii][Tt][Ll][Ee]:[[:space:]]*//p' "$1" 2> /dev/null | head -n 1 | sed -e 's/[[:space:]]*$//')
    print -r -- "${t:-${${1:t}:r}}"
}

__n_now () { LC_ALL=C date "$@"; }

__n_clipboard () {
    if __cc_has pbpaste
    then
        pbpaste
    elif __cc_has wl-paste
    then
        wl-paste
    elif __cc_has xclip
    then
        xclip -o -selection clipboard
    fi
}

__n_open_url () {
    if __cc_has open
    then
        open "$1"
    elif __cc_has xdg-open
    then
        xdg-open "$1" > /dev/null 2>&1
    else
        print -r -- "$1"
    fi
}

# Open FILE (at LINE) in Emacs if a server answers, else in $VISUAL/$EDITOR.
__n_edit () {
    local f=$1 line=${2:-}
    if [[ -n ${NOTES_EDITOR:-} ]]
    then
        ${=NOTES_EDITOR} ${line:++$line} "$f"
    elif __cc_has emacsclient && emacsclient -e t > /dev/null 2>&1
    then
        emacsclient -t ${line:++$line} "$f"
    else
        ${VISUAL:-${EDITOR:-vi}} ${line:++$line} "$f"
    fi
}

# ---- topics --------------------------------------------------------------
__n_topics () {
    local root=${NOTES_DIR%/} d rel
    for d in $root/**/*(/N)
    do
        rel=${d#$root/}
        [[ $rel == diary(|/*) ]] && continue
        print -r -- "$rel"
    done
}

# TAB-separated, newest first: topic, then "N notes · Nd — what its index says".
__n_topic_lines () {
    emulate -L zsh
    setopt extendedglob null_glob
    zmodload -F zsh/stat b:zstat 2> /dev/null
    zmodload zsh/datetime 2> /dev/null
    local root=${NOTES_DIR%/} rel
    local -a files newest st
    for rel in ${(f)"$(__n_topics)"}
    do
        files=($root/$rel/*.org(N))
        files=(${files:#*/index.org})
        newest=($root/$rel/*.org(Nom[1]))
        local days='' mt=0 desc=''
        if (( $#newest )) && zstat -A st +mtime $newest[1] 2> /dev/null
        then
            mt=$st[1]
            days=" · $(( (EPOCHSECONDS - mt) / 86400 ))d"
        fi
        [[ -f $root/$rel/index.org ]] \
            && desc=$(sed -n '/^[^:#*[:space:]-]/{p;q;}' "$root/$rel/index.org" | cut -c1-60)
        print -r -- "$mt"$'\t'"$rel"$'\t'"$#files notes${days}${desc:+ — $desc}"
    done | sort -rn | cut -f2-
}

# `Work Stuff/Infra' -> `work-stuff/infra'
__n_topic_name () {
    emulate -L zsh
    local s out=''
    for s in ${(s:/:)1}
    do
        out+=${out:+/}$(__n_slug "$s")
    done
    print -r -- "$out"
}

# Ask where a note goes; sets REPLY.  A topic that does not exist is made.
__n_pick_topic () {
    emulate -L zsh
    local root=${NOTES_DIR%/} topic='' key='' query='' sel=''
    local -a out
    if __cc_has fzf && [[ -t 1 ]]
    then
        out=("${(@f)$(__n_topic_lines | fzf --print-query --expect=ctrl-n \
            --delimiter=$'\t' --with-nth=1,2 --tabstop=36 --height=60% --reverse \
            --prompt='Put the note in> ' \
            --header='enter: pick · ctrl-n: new topic from what you typed' \
            --preview="head -n 20 ${(q)root}/{1}/index.org 2> /dev/null")}")
        query=$out[1]
        key=$out[2]
        sel=${out[3]%%$'\t'*}
        if [[ $key == ctrl-n || -z $sel ]]
        then
            topic=$query
        else
            topic=$sel
        fi
    else
        __n_topics | sed 's/^/  /' >&2
        read -r "topic?Put the note in (existing or new topic): " || return 1
    fi
    local -a segs
    segs=(${(s:/:)topic})
    local s
    topic=''
    for s in $segs
    do
        topic+=${topic:+/}$(__n_slug "$s")
    done
    [[ -n $topic ]] || { __n_die "a note needs a topic"; return 1 }
    if [[ ! -d $root/$topic ]]
    then
        local ans
        read -r "ans?Create the new topic '$topic'? [y/N] " || return 1
        [[ $ans == [yY]* ]] || { __n_die cancelled; return 1 }
    fi
    REPLY=$topic
}

# ---- creating ------------------------------------------------------------
# __n_create TOPIC TITLE [TAGS] [BODY]  ->  prints the new file
__n_create () {
    emulate -L zsh
    local root=${NOTES_DIR%/} topic=$1 title=$2 tags=${3:-} body=${4:-}
    local dir=$root/$topic slug file n=1
    [[ -n ${title//[[:space:]]/} ]] || { __n_die "a note needs a title"; return 1 }
    slug=$(__n_slug "$title")
    command mkdir -p -- "$dir"
    file=$dir/$slug.org
    while [[ -e $file ]]
    do
        (( n++ ))
        file=$dir/$slug-$n.org
    done
    {
        print -r -- "#+title: ${title}"
        print -r -- "#+date: $(__n_now '+[%Y-%m-%d %a]')"
        if [[ -n $tags ]]
        then
            local -a tl
            tl=(${(s: :)${tags//[,:]/ }})
            print -r -- "#+filetags: :${(j.:.)tl}:"
        fi
        print
        [[ -n $body ]] && print -r -- "$body"
    } > "$file"
    __n_index_up "$dir"
    print -r -- "$file"
}

# n new [topic] [title]
__n_new () {
    emulate -L zsh
    __n_check || return 1
    local topic=${1:-} title=${2:-} file
    if [[ -z $topic ]]
    then
        __n_pick_topic || return 1
        topic=$REPLY
    else
        topic=$(__n_topic_name "$topic")
    fi
    [[ -n $title ]] || vared -p 'Title: ' -c title
    file=$(__n_create "$topic" "$title") || return 1
    print -r -- "${file#${NOTES_DIR%/}/}"
    __n_edit "$file"
}

# n capture [-t topic] [-T title] [-g tags] [-c] [text...]   (or pipe text in)
__n_capture () {
    emulate -L zsh
    __n_check || return 1
    local topic='' title='' tags='' clip=0 text='' file
    while [[ ${1:-} == -* ]]
    do
        case $1 in
            -t) topic=$2; shift 2 ;;
            -T) title=$2; shift 2 ;;
            -g) tags=$2; shift 2 ;;
            -c) clip=1; shift ;;
            --) shift; break ;;
            *) __n_die "capture: unknown option $1"; return 2 ;;
        esac
    done
    if (( clip ))
    then
        text=$(__n_clipboard)
    elif (( $# ))
    then
        text=$*
    elif [[ ! -t 0 ]]
    then
        text=$(cat)
    else
        vared -p 'Note: ' -c text
    fi
    [[ -n ${text//[[:space:]]/} ]] || { __n_die "nothing to capture"; return 1 }
    if [[ -z $title ]]
    then
        title=${${(f)text}[1]}
        title=${title[1,60]}
        vared -p 'Title: ' -c title
    fi
    if [[ -z $topic ]]
    then
        __n_pick_topic || return 1
        topic=$REPLY
    else
        topic=$(__n_topic_name "$topic")
    fi
    local body=$text
    [[ $text == *$'\n'* ]] && body="#+begin_quote"$'\n'"$text"$'\n'"#+end_quote"
    file=$(__n_create "$topic" "$title" "$tags" "$body") || return 1
    print -r -- "captured in ${file#${NOTES_DIR%/}/}"
}

# ---- finding -------------------------------------------------------------
__n_note_lines () {
    local root=${NOTES_DIR%/}
    (
        cd "$root" || exit 1
        find . -name '*.org' -not -path './.*' -not -path './diary/*' -print0 \
            | xargs -0 grep -m1 -i '^#+title:' 2> /dev/null
    ) | sed -E 's|^\./([^:]*):#\+[Tt][Ii][Tt][Ll][Ee]:[[:space:]]*(.*)$|\2	\1|' | sort -f
}

# n find [query]
__n_find () {
    emulate -L zsh
    __n_check || return 1
    local root=${NOTES_DIR%/} sel
    if __cc_has fzf && [[ -t 1 ]]
    then
        sel=$(__n_note_lines | fzf --query="${*:-}" --delimiter=$'\t' --with-nth=1,2 \
            --tabstop=48 --height=70% --reverse --prompt='Note> ' \
            --preview="head -n 40 ${(q)root}/{2}") || return 0
    else
        sel=$(__n_note_lines | grep -i -- "${*:-.}" | head -n 1)
    fi
    [[ -n $sel ]] || { __n_die "no note found"; return 1 }
    __n_edit "$root/${sel#*$'\t'}"
}

# n search pattern
__n_search () {
    emulate -L zsh
    __n_check || return 1
    local root=${NOTES_DIR%/} sel
    (( $# )) || { __n_die "usage: n search <pattern>"; return 2 }
    local -a hits
    if __cc_has rg
    then
        hits=("${(@f)$(rg --line-number --no-heading --color=never --glob '*.org' -- "$*" "$root" 2> /dev/null)}")
    else
        hits=("${(@f)$(grep -rn --include='*.org' --exclude-dir='.*' -- "$*" "$root" 2> /dev/null)}")
    fi
    (( $#hits )) && [[ -n $hits[1] ]] || { __n_die "nothing matches '$*'"; return 1 }
    if __cc_has fzf && [[ -t 1 ]]
    then
        sel=$(print -rl -- $hits | sed "s|^$root/||" \
            | fzf --delimiter=: --height=70% --reverse --prompt='Search> ') || return 0
        local f=${sel%%:*} rest=${sel#*:}
        __n_edit "$root/$f" "${rest%%:*}"
    else
        print -rl -- $hits | sed "s|^$root/||"
    fi
}

# n cd [topic]
__n_cd () {
    emulate -L zsh
    __n_check || return 1
    if [[ -n ${1:-} && -d ${NOTES_DIR%/}/$1 ]]
    then
        cd "${NOTES_DIR%/}/$1"
    elif __cc_has fzf && [[ -t 1 ]]
    then
        local sel
        sel=$(__n_topic_lines | fzf --delimiter=$'\t' --with-nth=1,2 --tabstop=36 \
            --height=60% --reverse --prompt='cd> ' --query="${*:-}") || return 0
        cd "${NOTES_DIR%/}/${sel%%$'\t'*}"
    else
        cd "${NOTES_DIR%/}"
    fi
}

# ---- todos & habits --------------------------------------------------------
# n todo "text"  -- into the Inbox of todo.org, the way Emacs captures it
__n_todo_add () {
    emulate -L zsh
    __n_check || return 1
    local text="$*" file=${NOTES_DIR%/}/todo.org
    [[ -n $text ]] || vared -p 'Todo: ' -c text
    [[ -n ${text//[[:space:]]/} ]] || { __n_die "nothing to add"; return 1 }
    [[ -f $file ]] || printf '#+title: Todo\n\n* Inbox\n' > "$file"
    local entry="** TODO ${text}"$'\n'":PROPERTIES:"$'\n'":CREATED: $(__n_now '+[%Y-%m-%d %a %H:%M]')"$'\n'":END:"$'\n'
    ENTRY=$entry awk '
        function put() { printf "%s", ENVIRON["ENTRY"]; printf "%s", blanks; blanks = ""; done = 1 }
        {
            if (inb) {
                if ($0 ~ /^\* /) { put(); inb = 0; print; next }
                if ($0 ~ /^[ \t]*$/) { blanks = blanks $0 "\n"; next }
                printf "%s", blanks; blanks = ""; print; next
            }
            if ($0 ~ /^\* Inbox[ \t]*$/) inb = 1
            print
        }
        END { if (inb) put(); if (!done) { print "* Inbox"; printf "%s", ENVIRON["ENTRY"] } }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    print -r -- "added to the inbox: $text"
}

# n todos -- every open TODO/WIP/REVIEWING in the notes; pick one to open it
__n_todos () {
    emulate -L zsh
    __n_check || return 1
    local root=${NOTES_DIR%/}
    local -a hits
    if __cc_has rg
    then
        hits=("${(@f)$(rg --line-number --no-heading --color=never --glob '*.org' \
            '^\*+ (TODO|WIP|REVIEWING) ' "$root" 2> /dev/null | sed "s|^$root/||")}")
    else
        hits=("${(@f)$(grep -rnE --include='*.org' --exclude-dir='.*' '^\*+ (TODO|WIP|REVIEWING) ' "$root" 2> /dev/null | sed "s|^$root/||")}")
    fi
    [[ -n $hits[1] ]] || { print "no open todos"; return 0 }
    if __cc_has fzf && [[ -t 1 ]]
    then
        local sel
        sel=$(print -rl -- $hits | fzf --delimiter=: --height=70% --reverse --prompt='Todo> ') || return 0
        local f=${sel%%:*} rest=${sel#*:}
        __n_edit "$root/$f" "${rest%%:*}"
    else
        print -rl -- $hits
    fi
}

# Birthdays within N days (default 30), from the :BIRTHDAY: properties.
__n_birthdays () {
    emulate -L zsh
    __n_check || return 1
    zmodload zsh/datetime 2> /dev/null
    local days=${1:-30} file=${NOTES_DIR%/}/contacts.org
    [[ -f $file ]] || { __n_die "no contacts.org"; return 1 }
    local today t0 ty name b y m d t diff age
    strftime -s today '%Y-%m-%d' $EPOCHSECONDS
    strftime -r -s t0 '%Y-%m-%d' $today
    ty=${today%%-*}
    local -a rows
    local line
    while IFS=$'\t' read -r name b
    do
        [[ $b =~ '^(([0-9]{4})-|--)?([0-9]{2})-([0-9]{2})$' ]] || continue
        y=${match[2]:-}; m=${match[3]}; d=${match[4]}
        strftime -r -s t '%Y-%m-%d' "$ty-$m-$d" 2> /dev/null || strftime -r -s t '%Y-%m-%d' "$ty-$m-28"
        (( t < t0 )) && { strftime -r -s t '%Y-%m-%d' "$((ty + 1))-$m-$d" 2> /dev/null || strftime -r -s t '%Y-%m-%d' "$((ty + 1))-$m-28" }
        diff=$(( (t - t0 + 43200) / 86400 ))
        (( diff <= days )) || continue
        age=''
        [[ -n $y ]] && { strftime -s age '%Y' $t; age=" ($(( age - y )))" }
        rows+=("$(printf '%05d' $diff)"$'\t'"$diff"$'\t'"🎂 $name$age"$'\t'"$m-$d")
    done < <(awk '/^\* /{name=substr($0,3)} /^:BIRTHDAY:/{b=$2; print name "\t" b}' "$file")
    (( $#rows )) || { print "no birthdays in the next $days days"; return 0 }
    local r
    for r in ${(o)rows}
    do
        local f=("${(@s:	:)r}")
        if (( f[2] == 0 ))
        then
            printf '  %-9s %s\n' today "$f[3]"
        elif (( f[2] == 1 ))
        then
            printf '  %-9s %s\n' tomorrow "$f[3]"
        else
            printf '  in %-6s %s  %s\n' "${f[2]}d" "$f[3]" "$f[4]"
        fi
    done
}

# Habits whose next date is today or past, from habits.org.
__n_habits_due () {
    local file=${NOTES_DIR%/}/habits.org
    [[ -f $file ]] || return 0
    awk -v today="$(__n_now +%F)" '
        /^\*+ TODO/ { t = $0; sub(/^\*+ TODO +/, "", t); next }
        /SCHEDULED: </ && t != "" {
            match($0, /<[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)
            d = substr($0, RSTART + 1, 10)
            if (d <= today) print "  ◌ " t "  (" d ")"
            t = ""
        }' "$file"
}

# n today -- birthdays, habits due, the inbox
__n_today () {
    emulate -L zsh
    __n_check || return 1
    local b h i
    b=$(__n_birthdays 7 2> /dev/null)
    h=$(__n_habits_due)
    i=$(awk '/^\* Inbox/{inb=1; next} /^\* /{inb=0} inb && /^\*+ TODO/{sub(/^\*+ TODO +/,""); print "  ☐ " $0}' "${NOTES_DIR%/}/todo.org" 2> /dev/null)
    print -P "%B${CC_ACCENT_OUT:-}today%b $(__n_now '+%a %d %b')" 2> /dev/null || print "today"
    [[ -n $b && $b != no\ birthdays* ]] && { print "\nBirthdays"; print -r -- "$b" }
    [[ -n $h ]] && { print "\nHabits due"; print -r -- "$h" }
    [[ -n $i ]] && { print "\nInbox"; print -r -- "$i" }
    [[ -z $h && -z $i && ( -z $b || $b == no\ birthdays* ) ]] && print "\nnothing pending."
    return 0
}

# ---- contacts --------------------------------------------------------------
__n_contact_lines () {
    awk '
        function flush() { if (name != "") print name "\t" email "\t" phone "\t" bd }
        /^\* / { flush(); name = substr($0, 3); email = phone = bd = ""; next }
        /^:EMAIL:/ { sub(/^:EMAIL:[ \t]*/, ""); email = $0 }
        /^:PHONE:/ { sub(/^:PHONE:[ \t]*/, ""); phone = $0 }
        /^:BIRTHDAY:/ { sub(/^:BIRTHDAY:[ \t]*/, ""); bd = $0 }
        END { flush() }' "${NOTES_DIR%/}/contacts.org"
}

# n contact [query] -- pick one; prints Name <email> and copies it
__n_contact () {
    emulate -L zsh
    __n_check || return 1
    [[ -f ${NOTES_DIR%/}/contacts.org ]] || { __n_die "no contacts.org"; return 1 }
    local sel
    if __cc_has fzf && [[ -t 1 ]]
    then
        sel=$(__n_contact_lines | fzf --query="${*:-}" --delimiter=$'\t' --tabstop=28 \
            --height=50% --reverse --prompt='Contact> ') || return 0
    else
        __n_contact_lines | grep -i -- "${*:-.}"
        return 0
    fi
    local -a f
    f=("${(@s:	:)sel}")
    local out=$f[1]
    [[ -n ${f[2]:-} ]] && out="$f[1] <$f[2]>"
    print -r -- "$out"
    [[ -n ${f[3]:-} ]] && print -r -- "  $f[3]"
    __cc_has pbcopy && print -rn -- "${f[2]:-$f[1]}" | pbcopy
}

# n contact add NAME [EMAIL] [PHONE] [BIRTHDAY]
__n_contact_add () {
    emulate -L zsh
    __n_check || return 1
    local file=${NOTES_DIR%/}/contacts.org name=${1:-} email=${2:-} phone=${3:-} bd=${4:-}
    [[ -n $name ]] || vared -p 'Name: ' -c name
    [[ -n $name ]] || { __n_die "a contact needs a name"; return 1 }
    if [[ -n $bd && ! $bd =~ '^(([0-9]{4})-|--)?[0-9]{2}-[0-9]{2}$' ]]
    then
        __n_die "a birthday is YYYY-MM-DD or MM-DD, not '$bd'"
        return 1
    fi
    [[ -f $file ]] || printf '#+title: Contacts\n\n' > "$file"
    [[ -z $(tail -c1 "$file") ]] || print >> "$file"
    {
        print -r -- "* $name"
        if [[ -n $email$phone$bd ]]
        then
            print ":PROPERTIES:"
            [[ -n $email ]] && print -r -- ":EMAIL: $email"
            [[ -n $phone ]] && print -r -- ":PHONE: $phone"
            [[ -n $bd ]] && print -r -- ":BIRTHDAY: $bd"
            print ":END:"
        fi
    } >> "$file"
    print -r -- "added $name"
}

# ---- bookmarks -------------------------------------------------------------
# title <TAB> category <TAB> url, one per link
__n_bookmark_lines () {
    awk '
        /^\*+ / { match($0, /^\*+/); lvl = RLENGTH; t = substr($0, lvl + 2); sub(/ +$/, "", t)
                  st[lvl] = t; for (k = lvl + 1; k <= mx; k++) delete st[k]; mx = lvl; next }
        {
            s = $0
            while (match(s, /\[\[https?:\/\/[^]]+\](\[[^]]*\])?\]/)) {
                l = substr(s, RSTART + 2, RLENGTH - 3); s = substr(s, RSTART + RLENGTH)
                url = l; title = ""
                if (i = index(l, "][")) { url = substr(l, 1, i - 1); title = substr(l, i + 2) }
                cat = ""
                for (k = 1; k <= mx; k++) cat = cat (k > 1 ? " / " : "") st[k]
                print (title == "" ? url : title) "\t" cat "\t" url
            }
        }' "${NOTES_DIR%/}/bookmarks.org"
}

# n bookmark [query]  -> open
__n_bookmark_open () {
    emulate -L zsh
    __n_check || return 1
    [[ -f ${NOTES_DIR%/}/bookmarks.org ]] || { __n_die "no bookmarks.org"; return 1 }
    local sel
    if __cc_has fzf && [[ -t 1 ]]
    then
        sel=$(__n_bookmark_lines | fzf --query="${*:-}" --delimiter=$'\t' --with-nth=1,2 \
            --tabstop=60 --height=70% --reverse --prompt='Bookmark> ') || return 0
    else
        sel=$(__n_bookmark_lines | grep -i -- "${*:-.}" | head -n 1)
    fi
    [[ -n $sel ]] || return 1
    __n_open_url "${sel##*$'\t'}"
}

# n bookmark add URL [title] [category]
__n_bookmark_add () {
    emulate -L zsh
    __n_check || return 1
    local file=${NOTES_DIR%/}/bookmarks.org url=${1:-} title=${2:-} cat=${3:-}
    [[ -f $file ]] || { __n_die "no bookmarks.org"; return 1 }
    [[ -n $url ]] || { local clip; clip=$(__n_clipboard); [[ $clip == http*://* ]] && url=$clip; vared -p 'URL: ' -c url }
    [[ $url == http*://* ]] || { __n_die "that is not a URL: $url"; return 1 }
    if grep -qF -- "[[$url]" "$file"
    then
        print "already bookmarked: $(__n_bookmark_lines | awk -F'\t' -v u="$url" '$3==u{print $2; exit}')"
        return 0
    fi
    if [[ -z $title ]]
    then
        title=$(curl -sL --max-time 4 -- "$url" 2> /dev/null \
            | sed -n 's/.*<[Tt][Ii][Tt][Ll][Ee][^>]*>\(.*\)<\/[Tt][Ii][Tt][Ll][Ee]>.*/\1/p' | head -n 1)
        vared -p 'Title: ' -c title
    fi
    [[ -n $title ]] || title=$url
    if [[ -z $cat ]]
    then
        local -a cats
        cats=("${(@f)$(awk '/^\*+ /{match($0,/^\*+/); l=RLENGTH; t=substr($0,l+2); sub(/ +$/,"",t); st[l]=t; for(k=l+1;k<=m;k++)delete st[k]; m=l; p=""; for(k=1;k<=l;k++)p=p (k>1?" / ":"") st[k]; print p}' "$file")}")
        if __cc_has fzf && [[ -t 1 ]]
        then
            local -a out
            out=("${(@f)$(print -rl -- $cats | fzf --print-query --expect=ctrl-n --height=50% --reverse \
                --prompt='Category> ' --header='enter: pick · ctrl-n: new category from what you typed')}")
            if [[ ${out[2]:-} == ctrl-n || -z ${out[3]:-} ]]
            then
                cat=$out[1]
            else
                cat=$out[3]
            fi
        else
            print -rl -- $cats >&2
            read -r "cat?Category: "
        fi
    fi
    [[ -n $cat ]] || { __n_die "a bookmark needs a category"; return 1 }
    local item="- [[${url}][${title}]]"
    ITEM=$item TARGET=$cat awk '
        function put() { printf "%s\n", ENVIRON["ITEM"]; printf "%s", blanks; blanks = ""; done = 1 }
        BEGIN { n = split(ENVIRON["TARGET"], T, " / ") }
        {
            if ($0 ~ /^\*+ /) {
                if (inb) { put(); inb = 0 }
                match($0, /^\*+/); lvl = RLENGTH; t = substr($0, lvl + 2); sub(/ +$/, "", t)
                st[lvl] = t; for (k = lvl + 1; k <= mx; k++) delete st[k]; mx = lvl
                if (!done && lvl == n) { ok = 1; for (k = 1; k <= n; k++) if (st[k] != T[k]) ok = 0; if (ok) inb = 1 }
                print; next
            }
            if (inb) {
                if ($0 ~ /^[ \t]*$/) { blanks = blanks $0 "\n"; next }
                printf "%s", blanks; blanks = ""; print; next
            }
            print
        }
        END {
            if (inb) put()
            if (!done) {
                for (k = 1; k <= n; k++) { s = ""; for (j = 0; j < k; j++) s = s "*"; print s " " T[k] }
                printf "%s\n", ENVIRON["ITEM"]
            }
        }' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    print -r -- "bookmarked under $cat"
}

__n_bookmark () {
    case ${1:-} in
        add) shift; __n_bookmark_add "$@" ;;
        *) __n_bookmark_open "$@" ;;
    esac
}

# ---- index pages -----------------------------------------------------------
__n_index_dir_ok () {
    local root=${NOTES_DIR%/} dir=${1%/} rel
    [[ $dir == $root || $dir == $root/* ]] || return 1
    rel=${dir#$root}; rel=${rel#/}
    [[ -z $rel || $rel == .archive ]] && return 0
    [[ $rel == (.git|.metals)(|/*) ]] && return 1
    [[ $rel == diary(|/*) ]] && return 1
    rel=${rel#.archive/}
    [[ $rel == (.*|*/.*) ]] && return 1
    return 0
}

# Rebuild the generated part of DIR/index.org (an index without the markers is
# somebody's own page and is left alone).  Same format as notes.el writes.
__n_index_update () {
    emulate -L zsh
    setopt extendedglob null_glob
    local root=${NOTES_DIR%/} dir=${1%/}
    __n_index_dir_ok "$dir" || return 0
    local file=$dir/index.org old=''
    [[ -f $file ]] && old=$(< "$file")
    if [[ -n $old && $old != *'# BEGIN GENERATED INDEX'* && $old != *'# This index is generated'* ]]
    then
        return 0
    fi
    local -a subs notes any
    local d f
    for d in $dir/*(/N)
    do
        [[ ${d:t} == diary ]] && continue
        __n_index_dir_ok "$d" || continue
        any=($d/**/*.org(N[1]))
        (( $#any )) || continue
        [[ -f $d/index.org ]] || __n_index_update "$d"
        [[ -f $d/index.org ]] || continue
        subs+=("$(__n_pretty ${d:t})"$'\t'"./${d:t}/index.org")
    done
    if [[ $dir != $root ]]
    then
        for f in $dir/*.org(N)
        do
            [[ ${f:t} == index.org ]] && continue
            notes+=("$(__n_title $f)"$'\t'"./${f:t}")
        done
    fi
    # code-point order, as Emacs sorts the titles (an emoji sorts after letters)
    local LC_COLLATE=C
    subs=(${(oi)subs})
    notes=(${(oi)notes})
    local body='' e
    if (( $#subs ))
    then
        body+="* Topics"$'\n'
        for e in $subs
        do
            body+="- [[file:${e#*$'\t'}][${e%%$'\t'*}]]"$'\n'
        done
    fi
    if (( $#notes ))
    then
        body+="* Notes"$'\n'
        for e in $notes
        do
            body+="- [[file:${e#*$'\t'}][${e%%$'\t'*}]]"$'\n'
        done
    fi
    [[ -z $body && $dir != $root ]] && return 0

    local head='' desc='' tail=''
    local -a L
    local i=1 j n
    if [[ -n $old ]]
    then
        L=("${(@f)old}")
        n=$#L
        if [[ $L[1] == ':PROPERTIES:' ]]
        then
            while (( i <= n )) && [[ $L[i] != ':END:' ]]; do (( i++ )); done
            (( i++ ))
        fi
        local start=$i
        while (( i <= n )) && [[ $L[i] == '#+'* ]]; do (( i++ )); done
        (( i > start )) && head=${(F)L[1,i-1]}
    fi
    if [[ -z $head ]]
    then
        local rel=${dir#$root} title
        rel=${rel#/}
        if [[ -z $rel ]]
        then
            title=Notes
        else
            local -a segs parts
            segs=(${(s:/:)rel})
            local s
            for s in $segs; do parts+=("$(__n_pretty $s)"); done
            title=${(j: / :)parts}
        fi
        head="#+title: $title"$'\n'"#+date: $(__n_now '+[%Y-%m-%d %a]')"
    else
        j=$i
        while (( j <= n )) && [[ $L[j] != '*'* && $L[j] != '# BEGIN GENERATED INDEX' && $L[j] != '# This index'* ]]
        do
            (( j++ ))
        done
        desc=${(F)L[i,j-1]}
        desc=${desc##[[:space:]]##}
        desc=${desc%%[[:space:]]##}
        local k=0 m=0 idx
        for (( idx = i; idx <= n; idx++ ))
        do
            if [[ $L[idx] == '# END GENERATED INDEX' ]]; then k=$idx; break; fi
        done
        if (( k ))
        then
            tail=${(F)L[k+1,n]}
        else
            for (( idx = i; idx <= n; idx++ ))
            do
                if [[ $L[idx] == '* Not indexed here' ]]; then m=$idx; break; fi
            done
            if (( m ))
            then
                local e2=$n
                for (( idx = m; idx <= n; idx++ ))
                do
                    if [[ $L[idx] == '# This index'* ]]; then e2=$(( idx - 1 )); break; fi
                done
                tail=${(F)L[m,e2]}
            fi
        fi
        tail=${tail##[[:space:]]##}
        tail=${tail%%[[:space:]]##}
    fi
    local out="$head"$'\n\n'
    [[ -n $desc ]] && out+="$desc"$'\n\n'
    out+="# BEGIN GENERATED INDEX"$'\n'"$body# END GENERATED INDEX"$'\n'
    [[ -n $tail ]] && out+=$'\n'"$tail"$'\n'
    command mkdir -p -- "$dir"
    print -rn -- "$out" > "$file.tmp"
    if [[ -f $file ]] && cmp -s "$file.tmp" "$file"
    then
        rm -f -- "$file.tmp"
        return 0
    fi
    mv -- "$file.tmp" "$file"
    REPLY=written
}

# The index of DIR and of every folder above it, up to the notes root.
__n_index_up () {
    local root=${NOTES_DIR%/} d=${1%/}
    while [[ $d == $root || $d == $root/* ]]
    do
        __n_index_update "$d"
        [[ $d == $root ]] && break
        d=${d:h}
    done
}

# n index -- every index page, children first
__n_index_all () {
    emulate -L zsh
    setopt null_glob
    __n_check || return 1
    local root=${NOTES_DIR%/} d count=0
    local -a dirs
    dirs=($root/**/*(/N))
    [[ -d $root/.archive ]] && dirs+=($root/.archive $root/.archive/**/*(/N))
    # deepest first
    dirs=(${(@)${(f)"$(for d in $dirs; do print -r -- "${#${(s:/:)d}} $d"; done | sort -rn | cut -d' ' -f2-)"}})
    for d in $dirs $root
    do
        REPLY=''
        __n_index_update "$d"
        [[ $REPLY == written ]] && (( count++ ))
    done
    print "indexes: $count written"
}

# ---- the command -----------------------------------------------------------
n () {
    local cmd=${1:-help}
    (( $# )) && shift
    case $cmd in
        c | capture) __n_capture "$@" ;;
        new) __n_new "$@" ;;
        f | find | open) __n_find "$@" ;;
        s | search | grep) __n_search "$@" ;;
        x | todo | add) __n_todo_add "$@" ;;
        t | todos) __n_todos "$@" ;;
        d | today) __n_today ;;
        b | bookmark | bm) __n_bookmark "$@" ;;
        k | contact) if [[ ${1:-} == add ]]; then shift; __n_contact_add "$@"; else __n_contact "$@"; fi ;;
        u | birthdays) __n_birthdays "$@" ;;
        i | index) __n_index_all ;;
        cd) __n_cd "$@" ;;
        dir) print -r -- "${NOTES_DIR%/}" ;;
        h | help | -h | --help)
            cat <<'EOF'
n — notes from the terminal (same files as Emacs)

  n capture [-t topic] [-T title] [-g tags] [-c] [text]
                            file text (args, a pipe, or -c the clipboard) as a note;
                            asks where it goes, with completion when fzf is there
  n new [topic] [title]     write a new note in $EDITOR (Emacs if a server runs)
  n find [query]            pick a note by title and open it
  n search <pattern>        search the text of every note
  n todo <text>             add a TODO to the inbox (todo.org)
  n todos                   every open TODO in the notes; pick one to open it
  n today                   birthdays this week, habits due, the inbox
  n bookmark [query]        pick a bookmark and open it
  n bookmark add [url [title [category]]]
                            file a URL (default: the clipboard) under a category
  n contact [query]         pick a contact; prints and copies the address
  n contact add <name> [email] [phone] [birthday]
  n birthdays [days]        birthdays coming up (default 30 days)
  n index                   regenerate every topic's index.org
  n cd [topic]              cd into a topic folder
  n dir                     print the notes directory ($NOTES_DIR)
EOF
            ;;
        *)
            print -u2 "n: unknown command '$cmd' (try: n help)"
            return 2
            ;;
    esac
}

alias nc='n capture'
alias nf='n find'
alias nx='n todo'
alias nt='n today'

if (( $+functions[compdef] ))
then
    _n () {
        local -a cmds
        cmds=(
            'capture:file text as a note'
            'new:write a new note'
            'find:find a note by title'
            'search:search the text of every note'
            'todo:add a todo to the inbox'
            'todos:open todos'
            'today:birthdays, habits due, the inbox'
            'bookmark:open or add a bookmark'
            'contact:find or add a contact'
            'birthdays:birthdays coming up'
            'index:regenerate the index pages'
            'cd:cd into a topic'
            'dir:print the notes directory'
            'help:list the commands'
        )
        if (( CURRENT == 2 ))
        then
            _describe -t commands 'n command' cmds
        elif [[ $words[2] == (cd|capture|c|new) ]] && (( CURRENT == 3 ))
        then
            local -a topics
            topics=(${(f)"$(__n_topics)"})
            _describe -t topics 'topic' topics
        fi
    }
    compdef _n n
fi
