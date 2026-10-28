;;; cask-and-cons

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; cask-and-cons is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; cask-and-cons is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with cask-and-cons.  If not, see <https://www.gnu.org/licenses/>.

(define-module (cask-and-cons zsh)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:use-module (ice-9 textual-ports)
  #:use-module (cask-and-cons prelude)
  #:use-module (cask-and-cons user-settings)
  #:export (zsh-identity zsh-shell-lib-filename zsh-lesskey-filename
                         zsh-notes-lib-filename zsh-notes-exports
                         zsh-read-source-file lesskey-config-dir
                         zsh-read-shell-lib zsh-read-notes-lib
                         serialize-zsh-assignment
                         zsh-completion-setopts zsh-shell-setopts
                                   zsh-history-setopts
                                   zsh-color-exports
                                   zsh-path-exports
                                   zsh-history-exports
                                   zsh-guile-exports
                                   zsh-sdkman-exports
                                   zsh-nvm-exports
                                   zsh-aliases
                                   zshrc-config
                                   install-zsh-config
                                   zsh-config-dir
                                   zshrc-filename))

;; Each setopt list holds plain symbols, rendered verbatim as `setopt NAME`.
;; Explanations are kept as regular Scheme comments next to the entry they
;; describe instead of being serialized into the generated `.zshrc`.

(define zsh-completion-setopts
  '(LIST_AMBIGUOUS ;like show-all-if-ambiguous
                   MARK_DIRS ;mark symlinked/completed dirs with /
                   COMPLETE_IN_WORD))
 ;; mark symlinked/completed dirs with /

(define zsh-shell-setopts
  '(AUTO_CD CORRECT ;like dirspell/cdspell (spelling correction for commands)
            CORRECT_ALL
            AUTO_PUSHD ;cd pushes the old directory, like a builtin dirs -v
            PUSHD_IGNORE_DUPS
            PUSHD_SILENT
            INTERACTIVE_COMMENTS ;allow # comments in an interactive shell
            NO_BEEP))
 ;; extends correction to all arguments (optional, close to dirspell)

(define zsh-history-setopts
  '(EXTENDED_HISTORY ;adds timestamps (like HISTTIMEFORMAT), shown via `history -i`
                     HIST_IGNORE_SPACE ;like HISTCONTROL=ignorespace
                     HIST_IGNORE_DUPS
                     HIST_IGNORE_ALL_DUPS ;closest to HISTCONTROL=erasedups
                     HIST_SAVE_NO_DUPS
                     HIST_FIND_NO_DUPS
                     HIST_REDUCE_BLANKS
                     INC_APPEND_HISTORY ;write each command to HISTFILE immediately
                     SHARE_HISTORY))
 ;; merge history from other sessions live

;; Alist of NAME -> VALUE, rendered as `export NAME="VALUE"`. Explanations
;; are kept as Scheme comments rather than being serialized.

(define zsh-color-exports
  '(("GREEN_TEXT" . "$(tput setaf 2)") ("RED_TEXT" . "$(tput setaf 1)")
    ("RESET_TEXT" . "$(tput sgr0)")
    ("BOLD_TEXT" . "$(tput bold)")))

(define zsh-path-exports
  '(("CDPATH" . ".:$HOME/Hacking:$HOME/Work")))

(define zsh-history-exports
  '(("HISTSIZE" . "500000") ("SAVEHIST" . "100000") ;replaces HISTFILESIZE
    ("HISTFILE" . "$HOME/.zsh_history")))

(define zsh-guile-exports
  '(("GUILE_LOAD_PATH" . "/opt/homebrew/share/guile/site/3.0")
    ("GUILE_LOAD_COMPILED_PATH" . "/opt/homebrew/lib/guile/3.0/site-ccache")
    ("GUILE_SYSTEM_EXTENSIONS_PATH" . "/opt/homebrew/lib/guile/3.0/extensions")))

(define zsh-sdkman-exports
  '(("SDKMAN_DIR" . "$HOME/.sdkman")))

(define zsh-nvm-exports
  '(("NVM_DIR" . "$HOME/.nvm")))

;; Alist of alias name -> command, rendered as `alias name="command"`.

(define zsh-shared-aliases
  ;; Navigation, emacs, podman, fetch, ...: the set every machine shares.
  '((".." . "cd ..;pwd")
    ("..." . "cd ../..;pwd")
    ("...." . "cd ../../..;pwd")
    ("c" . "clear")
    ("h" . "history")
    ("hg" . "hgrep")
    ("tree" . "tree --dirsfirst -F")
    ("mkdir" . "mkdir -p -v")
    ("df" . "df -h")
    ("e" . "emacsclient -t")
    ("k" . "pkill")
    ("fetch" . "fastfetch")
    ("vanilla-emacs" . "emacs -Q")
    ("restart-emacs" . "pkill emacs || true; pkill Emacs || true; emacs --daemon")
    ("docker" . "podman")
    ("docker-compose" . "podman compose")
    ("find-largest-files" . "du -h -x -s -- * 2>/dev/null | sort -r -h | head -20")))

;; One-line git shortcuts, as data: (NAME . BODY).  glog is multi-line and
;; stays in shell-lib.zsh.
(define zsh-git-shortcuts
  '(("gst" . "git status --short --branch \"$@\"")
    ("gd" . "git diff \"$@\"")
    ("gds" . "git diff --stat \"$@\"")
    ("gco" . "git checkout \"$@\"")
    ("gsw" . "git switch \"$@\"")
    ("gbr" . "git branch -vv \"$@\"")
    ("gcm" . "git commit -m \"$*\"")
    ("gpl" . "git pull --ff-only \"$@\"")
    ("gpu" . "git push \"$@\"")
    ("gfetch" . "git fetch --all --prune \"$@\"")
    ("groot" . "cdroot")))

;; The greeting pool: nerd-style sayings about free software, RMS, GNU, Emacs
;; and Linux/Unix.  Plain data; extend freely.  Keep in step with heks-bash.
(define zsh-greetings
  '(;; emacs
    "Vi Vi Vi is the number of the beast. Emacs is salvation."
    "M-x doctor. Tell me about your childhood."
    "Evaluating buffer... Enlightenment achieved."
    "C-x C-c. Are you sure you want to exit your entire reality?"
    "Your .emacs file has more lines of code than most corporate startups."
    "Emacs: The extensible, customizable, self-documenting, real-time display environment."
    "Emacs is a magnificent operating system, it just lacks a good text editor."
    "M-x butterfly"
    "Escape Meta Alt Control Shift. Your pinky finger is strong."
    "C-x C-s. Your progress is saved. Your soul is secure."
    "Welcome to the Church of Emacs. Emacs is my editor, and GNU is its operating system."
    "Living in the buffers since inception."
    "C-h t. Everyone starts as a beginner."
    "Everything is a buffer, until it's a window."
    "M-x emacs-uptime. Reboot? Never heard of it."
    "In Emacs, nobody can hear you C-g."
    "Lisp: the programmable programming language."
    "(lambda (x) x) -- the identity of a hacker."
    ;; gnu / rms / free software
    "GNU's Not Unix! Welcome to the recursive revolution."
    "Free software is a matter of liberty, not price. Think free speech, not free beer."
    "You are entering a 100% libre user space."
    "Guile, Guix, and Glory. Welcome to the GNU system."
    "Join us now and share the software; You'll be free, hackers, you'll be free."
    "Happy Hacking!"
    "There is no system but GNU, and Linux is one of its kernels."
    "If we do not control our software, our software controls us."
    "Proprietary software is a social problem. Keep your system clean."
    "With digital technology, sharing is easy. Sharing is good."
    "I'd just like to interject for a moment: what you're referring to as Linux is GNU/Linux."
    "The four freedoms: run, study, share, improve. Number zero is the best one."
    "Copyleft: all rights reversed."
    "Use free software. Your freedom is not a feature request."
    "Software wants to be free, and so do you."
    "Treat your source like a library book: share it."
    ;; unix / linux lore
    "Unix is user-friendly. It's just very selective about who its friends are."
    "In the beginning was the command line."
    "Everything is a file, until it's a process."
    "May the source be with you."
    "RTFM: Read The Fine Manual."
    "Pipe it, grep it, sed it, love it."
    "sudo make me a sandwich."
    "There's no place like 127.0.0.1."
    "rm -rf: the sharpest tool in the shed."
    "Keep calm and `man man`."
    "Linux: because a computer should do what you tell it to."
    "It's not a bug, it's an undocumented feature of the kernel."
    "chmod +x your life."
    "Talk is cheap. Show me the code."))

(define (shell-double-quote s)
  "Return @var{s} escaped for use inside a double-quoted shell string."
  (string-concatenate
   (map (lambda (c)
          (if (memv c '(#\\ #\" #\$ #\`))
              (string #\\ c)
              (string c)))
        (string->list s))))

(define (serialize-zsh-greetings)
  (string-append
   "CC_GREETINGS=(\n"
   (string-join (map (lambda (g)
                       (format #f "\t\"~a\"" (shell-double-quote g)))
                     zsh-greetings)
                "\n")
   "\n)\n"))

(define (serialize-zsh-function f)
  (format #f "~a () { ~a; }\n" (car f) (cdr f)))

(define zsh-aliases
  ;; Only what is truly machine specific.
  '(("ll" . "gls -lAh --group-directories-first")
    ("l" . "gls -lAh --group-directories-first")
    ("la" . "gls -lAh --group-directories-first")
    ("du" . "gdu -h")
    ("df" . "gdf -h")))

(define (mk-setopt-lines setopts)
  "Serialize a list of @var{setopts} names into one `setopt NAME` line per
entry.

@example
(mk-setopt-lines '(AUTO_CD CORRECT))
@result{} \"setopt AUTO_CD
setopt CORRECT
\"
@end example"
  (with-output-to-string (lambda ()
                           (for-each (lambda (name)
                                       (format #t "setopt ~a\n" name)) setopts))))

(define (mk-alias-lines aliases)
  "Serialize an alist of @var{aliases} (NAME . COMMAND) into one
`alias NAME=\"COMMAND\"` line per entry."
  (mk-kv-conf-lines aliases
                    #:template "alias ~a=\"~a\"\n"))

(define (mk-export-lines exports)
  "Serialize an alist of @var{exports} (NAME . VALUE) into one
`export NAME=\"VALUE\"` line per entry."
  (mk-kv-conf-lines exports
                    #:template "export ~a=\"~a\"\n"))

(define zsh-identity
  ;; Machine identity read by the shared shell library. These five knobs are
  ;; all it takes to make the prompt say "macOS laptop" instead of "server".
  '(("CC_FLAVOR" . "cask-and-cons")
    ("CC_HOST_KIND" . "macos")
    ("CC_SIGIL" . "⌘")
    ("CC_ACCENT" . "175")
    ("CC_RC_FILE" . "$HOME/.zshrc")))

(define zsh-shell-lib-filename
  (make-parameter "shell-lib.zsh"))

;; The notes helpers: the `n' command (capture, find, todo, bookmarks,
;; contacts, birthdays, index pages) for when Emacs is not at hand.  Plain
;; zsh next to this module, spliced into ~/.zshrc after the shared library.
(define zsh-notes-lib-filename
  (make-parameter "notes.zsh"))

;; Where the notes are: the same directory the Emacs bridge points at.
(define zsh-notes-exports
  `(("NOTES_DIR" . ,notes-directory)))

;; The pager keymap: a plain data file next to this module, shared verbatim
;; with heks-bash and wolk-jjba, installed as $XDG_CONFIG_HOME/lesskey.
(define zsh-lesskey-filename
  (make-parameter "lesskey"))

(define (serialize-zsh-assignment a)
  "Serialize a single @var{a} (@code{NAME . VALUE}) as a plain shell assignment.
Nothing is exported: the @code{CC_*} variables are only read by the shared
shell library."
  (format #f "~a=\"~a\"\n"
          (car a)
          (cdr a)))

(define (zsh-read-source-file name)
  "Return the contents of the repository file @var{name} as a string.
The file sits next to this module, so look there first and fall back to the
repository-relative path for setups that load compiled code."
  (let* ((here (and (current-filename)
                    (dirname (current-filename)))))
    (let loop
        ((paths (list (and here
                           (format #f "~a/~a" here name))
                      (format #f "src/cask-and-cons/~a" name))))
      (cond ((null? paths)
             (error "cask-and-cons: cannot find the shared file" name))
            ((and (car paths)
                  (file-exists? (car paths)))
             (call-with-input-file (car paths)
               get-string-all))
            (else (loop (cdr paths)))))))

(define (zsh-read-shell-lib)
  "Return the contents of the shared zsh library as a string."
  (zsh-read-source-file (zsh-shell-lib-filename)))

(define (zsh-read-notes-lib)
  "Return the contents of the notes helpers for zsh as a string."
  (zsh-read-source-file (zsh-notes-lib-filename)))

(define (lesskey-config-dir)
  "Directory less(1) searches first for its keymap: @env{XDG_CONFIG_HOME},
else @file{~/.config}."
  (let* ((home (or (getenv "HOME") "/tmp"))
         (xdg (getenv "XDG_CONFIG_HOME")))
    (if (and xdg (not (string-null? xdg)))
        xdg
        (format #f "~a/.config" home))))

(define zshrc-config
  (string-append
   "# cask-and-cons --- ZSH configuration\n"
   "# auto-generated file! Regenerate with `./caco install-zsh`.\n"
   "# Sources of truth: src/cask-and-cons/zsh.scm (machine data) and\n"
   "# src/cask-and-cons/shell-lib.zsh (shared prompt + helpers).\n"
   "\n"
   (mk-kv-conf-lines zsh-identity
                     #:template equal-conf-quote-value-pair)
   "\n"
   "include() { [[ -f \"$1\" ]] && . \"$1\"; }\n"
   "\n"
   "include /etc/zshrc\n"
   "\n"
   "# ---- line editor -----------------------------------------------------------\n"
   "[[ -o interactive ]] && include ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh\n"
   "bindkey '^I' expand-or-complete   # restore Tab for completion\n"
   "bindkey '^[[A' up-line-or-search\n"
   "bindkey '^[[B' down-line-or-search\n"
   "# fzf key bindings: CTRL-R history, CTRL-T files, ALT-C cd\n"
   "if [[ -o interactive ]] && (( $+commands[fzf] )); then\n"
   "    source <(fzf --zsh)\n"
   "fi\n"
   "\n"
   "# ---- completion ------------------------------------------------------------\n"
   "autoload -Uz compinit\n"
   "zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'\n"
   "zstyle ':completion:*' completer _complete _match _approximate\n"
   "zstyle ':completion:*' menu select\n"
   "zstyle ':completion:*' use-cache on\n"
   "zstyle ':completion:*' cache-path \"${XDG_CACHE_HOME:-$HOME/.cache}/zcompcache\"\n"
   "zstyle ':completion:*' group-name ''\n"
   "zstyle ':completion:*' list-colors \"${(s.:.)LS_COLORS}\"\n"
   "zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'\n"
   "compinit -C -d \"${XDG_CACHE_HOME:-$HOME/.cache}/zcompdump\"\n"
   "_comp_options+=(globdots)\n"
   "\n\n# ---- shell options ----\n"
   (mk-setopt-lines zsh-completion-setopts)
   "\n"
   (mk-setopt-lines zsh-shell-setopts)
   "\n# ---- environment ----\n"
   (mk-export-lines zsh-color-exports)
   "\n"
   (mk-export-lines zsh-path-exports)
   "\n# ---- history ----\n"
   (mk-export-lines zsh-history-exports)
   "\n"
   (mk-setopt-lines zsh-history-setopts)
   "\n\n"
   "# HISTIGNORE equivalent: pattern-based, via a zshaddhistory hook\n"
   "zshaddhistory() {\n"
   "    local line=${1%%$'\\n'}\n"
   "    [[ \"$line\" =~ ^( |cd|pwd|exit|ls|ll|l|bg|fg|history|clear)([[:space:]]|$) ]] && return 1\n"
   "    return 0\n"
   "}\n"
   "\n# ---- GUILE (Homebrew) ----\n"
   (mk-export-lines zsh-guile-exports)
   "\n"
   ;; the shared prompt engine, git segment, helpers and greeting pool
   (zsh-read-shell-lib)
   (serialize-zsh-greetings)
   (string-concatenate (map serialize-zsh-function zsh-git-shortcuts))
   "\n"
   ;; the notes: where they are, and the `n' command that works on them
   "# ---- notes (the `n' command) ----\n"
   (mk-export-lines zsh-notes-exports)
   (zsh-read-notes-lib)
   "\n"
   "# ---- macOS specifics -------------------------------------------------------\n"
   "brewu () {\n"
   "    brew update && brew upgrade && brew cleanup\n"
   "}\n"
   "\n"
   "flushdns () {\n"
   "    sudo dscacheutil -flushcache\n"
   "    sudo killall -HUP mDNSResponder\n"
   "}\n"
   "\n"
   "showfiles () {\n"
   "    defaults write com.apple.finder AppleShowAllFiles -bool true && killall Finder\n"
   "}\n"
   "\n"
   "hidefiles () {\n"
   "    defaults write com.apple.finder AppleShowAllFiles -bool false && killall Finder\n"
   "}\n"
   "\n"
   "# Native notifications; overrides the portable helper from the shared library.\n"
   "notify () {\n"
   "    osascript -e \"display notification \\\"$1\\\" with title \\\"${2:-$(hostname -s)}\\\"\" 2>/dev/null \\\n"
   "        || printf '\\a%s: %s\\n' \"${2:-$(hostname -s)}\" \"$1\"\n"
   "}\n"
   "\n"
   "# macOS has no ss(8): a readable listener list via lsof.\n"
   "ports () {\n"
   "    lsof -iTCP -sTCP:LISTEN -P -n\n"
   "}\n"
   "\n# ---- aliases ----\n"
   (mk-alias-lines zsh-shared-aliases)
   (mk-alias-lines zsh-aliases)
   "\n# ---- PATH ----\n"
   "path+=(\"$HOME/.bin\")\n"
   "path+=(\"$HOME/.local/bin\")\n"
   "path+=(\"$HOME/Downloads/kotlin-server-latest/bin\")\n"
   "export PATH\n"
   "\n"
   (mk-export-lines zsh-sdkman-exports)
   """
[[ -s \"$HOME/.sdkman/bin/sdkman-init.sh\" ]] && source \"$HOME/.sdkman/bin/sdkman-init.sh\"
"""
   (mk-export-lines zsh-nvm-exports)
   """
[ -s \"$NVM_DIR/nvm.sh\" ] && \\. \"$NVM_DIR/nvm.sh\"  # This loads nvm
[ -s \"$NVM_DIR/bash_completion\" ] && \\. \"$NVM_DIR/bash_completion\"  # This loads nvm bash_completion

# ---- boot: colours, prompt hook, greeting ---------------------------------
cc_boot
"""))

(define zsh-config-dir
  (make-parameter (format #f "~a"
                          (or (getenv "HOME") "/tmp"))))

(define zshrc-filename
  (make-parameter ".zshrc"))

(define (install-zsh-config)
  (log-info "Installing ZSH configuration")
  (load-local-overrides '(cask-and-cons zsh)
                        'zsh-settings)
  (install-config-file! #:name (zshrc-filename)
                        #:dir (zsh-config-dir)
                        #:contents zshrc-config)
  ;; The pager keymap lives outside the rc so less can read it directly.
  (let ((dir (lesskey-config-dir)))
    (unless (file-exists? dir)
      (system* "mkdir" "-p" dir))
    (install-config-file! #:name (zsh-lesskey-filename)
                          #:dir dir
                          #:contents (zsh-read-source-file
                                      (zsh-lesskey-filename))))

  (log-success "Installed ZSH configuration"))
