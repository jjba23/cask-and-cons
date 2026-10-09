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
  #:use-module (cask-and-cons prelude)
  #:use-module (cask-and-cons user-settings)
  #:export (zsh-completion-setopts
                             zsh-shell-setopts
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
  '(LIST_AMBIGUOUS    ;; like show-all-if-ambiguous
    MARK_DIRS))       ;; mark symlinked/completed dirs with /

(define zsh-shell-setopts
  '(AUTO_CD
    CORRECT           ;; like dirspell/cdspell (spelling correction for commands)
    CORRECT_ALL))     ;; extends correction to all arguments (optional, close to dirspell)

(define zsh-history-setopts
  '(EXTENDED_HISTORY       ;; adds timestamps (like HISTTIMEFORMAT), shown via `history -i`
    HIST_IGNORE_SPACE      ;; like HISTCONTROL=ignorespace
    HIST_IGNORE_DUPS
    HIST_IGNORE_ALL_DUPS   ;; closest to HISTCONTROL=erasedups
    HIST_SAVE_NO_DUPS
    HIST_FIND_NO_DUPS
    HIST_REDUCE_BLANKS
    INC_APPEND_HISTORY     ;; write each command to HISTFILE immediately
    SHARE_HISTORY))        ;; merge history from other sessions live

;; Alist of NAME -> VALUE, rendered as `export NAME="VALUE"`. Explanations
;; are kept as Scheme comments rather than being serialized.

(define zsh-color-exports
  '(("GREEN_TEXT" . "$(tput setaf 2)")
    ("RED_TEXT" . "$(tput setaf 1)")
    ("RESET_TEXT" . "$(tput sgr0)")
    ("BOLD_TEXT" . "$(tput bold)")))

(define zsh-path-exports
  '(("CDPATH" . ".:$HOME/Hacking:$HOME/Work")))

(define zsh-history-exports
  '(("HISTSIZE" . "500000")
    ("SAVEHIST" . "100000")   ;; replaces HISTFILESIZE
    ("HISTFILE" . "$HOME/.zsh_history")))

(define zsh-guile-exports
  '(("GUILE_LOAD_PATH" . "/opt/homebrew/share/guile/site/3.0")
    ("GUILE_LOAD_COMPILED_PATH" . "/opt/homebrew/lib/guile/3.0/site-ccache")
    ("GUILE_SYSTEM_EXTENSIONS_PATH"
     . "/opt/homebrew/lib/guile/3.0/extensions")))

(define zsh-sdkman-exports
  '(("SDKMAN_DIR" . "$HOME/.sdkman")))

(define zsh-nvm-exports
  '(("NVM_DIR" . "$HOME/.nvm")))

;; Alist of alias name -> command, rendered as `alias name="command"`.

(define zsh-aliases
  '((".." . "cd ..;pwd")
    ("..." . "cd ../..;pwd")
    ("...." . "cd ../../..;pwd")
    ("c" . "clear")
    ("h" . "history")
    ("tree" . "tree --dirsfirst -F")
    ("mkdir" . "mkdir -p -v")
    ("ll" . "gls -lAh --group-directories-first")
    ("l" . "gls -lAh --group-directories-first")
    ("e" . "emacsclient -t")
    ("k" . "pkill")
    ("fetch" . "fastfetch")
    ("vanilla-emacs" . "emacs -Q")
    ("restart-emacs" . "pkill Emacs && emacs --daemon")
    ("docker" . "podman")
    ("docker-compose" . "podman compose")
    ("find-largest-files" . "du -h -x -s -- * | sort -r -h | head -20")))

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
                                       (format #t "setopt ~a\n" name))
                                     setopts))))

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

(define zshrc-config
  (string-append
   "# cask-and-cons --- ZSH configuration

include() { [[ -f \"$1\" ]] && . \"$1\"; }

include /etc/zshrc

[[ -o interactive ]] && include ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
bindkey '^I' expand-or-complete   # restore Tab for completion (autosuggestions hijacks it)

# Completion-related options
autoload -Uz compinit && compinit
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'   # case-insensitive completion
zstyle ':completion:*' completer _complete _match
" (mk-setopt-lines zsh-completion-setopts) "
" (mk-setopt-lines zsh-shell-setopts) "
" (mk-export-lines zsh-color-exports) "
" (mk-export-lines zsh-path-exports) "
# --- History config ---
" (mk-export-lines zsh-history-exports) "
" (mk-setopt-lines zsh-history-setopts) "
# HISTIGNORE equivalent: pattern-based, via a zshaddhistory hook
zshaddhistory() {
    local line=${1%%$'\\n'}
    [[ \"$line\" =~ ^(\\ |exit|ls|ll|bg|fg|history|clear)([[:space:]]|$) ]] && return 1
    return 0
}

" (mk-export-lines zsh-guile-exports) "
setopt PROMPT_SUBST

PROMPT='%B%n@%m%b: %2~${GUIX_ENVIRONMENT:+ [env]}
%Bλ%b '

path+=(\"$HOME/.bin\")
path+=(\"$HOME/Downloads/kotlin-server-latest/bin\")
export PATH

" (mk-export-lines zsh-sdkman-exports) "
[[ -s \"$HOME/.sdkman/bin/sdkman-init.sh\" ]] && source \"$HOME/.sdkman/bin/sdkman-init.sh\"

" (mk-export-lines zsh-nvm-exports) "
[ -s \"$NVM_DIR/nvm.sh\" ] && \\. \"$NVM_DIR/nvm.sh\"  # This loads nvm
[ -s \"$NVM_DIR/bash_completion\" ] && \\. \"$NVM_DIR/bash_completion\"  # This loads nvm bash_completion

" (mk-alias-lines zsh-aliases)))

(define zsh-config-dir
  (make-parameter (format #f "~a"
                          (or (getenv "HOME") "/tmp"))))

(define zshrc-filename
  (make-parameter ".zshrc"))

(define (install-zsh-config)
  (log-info "Installing ZSH configuration")
  (load-local-overrides '(cask-and-cons zsh) 'zsh-settings)
  (install-config-file! #:name (zshrc-filename)
                        #:dir (zsh-config-dir)
                        #:contents zshrc-config)

  (log-success "Installed ZSH configuration"))
