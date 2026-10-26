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

;; Declarative list of Homebrew taps, formulae and casks.

(define-module (cask-and-cons brew)
  #:declarative? #f
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-1)
  #:use-module (cask-and-cons prelude)
  #:use-module (cask-and-cons user-settings)
  #:export (brew-taps brew-formulae brew-casks install-brew-packages))

(define brew-taps
  '("koekeishiya/formulae"
    "d12frosted/emacs-plus"
    "hashicorp/tap"))

(define brew-formulae
  '("jq" "fzf"
    "koekeishiya/formulae/skhd"
    "tree"
    "coreutils"
    "marksman"
    "gpg"
    "yaml-language-server"
    "apm"
    "azure-cli"
    "gh"
    "Azure/kubelogin/kubelogin"
    "k9s"
    "krew"
    "kubectx"
    "7zip"
    "guile"
    "kubectl"
    "ripgrep"
    "fd"
    "bat"
    "eza"
    "htop"
    "wget"
    "pinentry-mac"
    "watch"
    "git-delta"
    "yq"
    "tmux"
    "mongosh"
    "mas"
    "gnu-sed"
    "gawk"
    "shellcheck"
    "direnv"
    "zoxide"
    "jless"
    "tldr"
    "avro-tools"
    "kcat"
    "fx"
    "gron"
    "hashicorp/tap/terraform"
    "terraform-linters/tap/tflint"
    "terraform-docs"
    "terragrunt"
    "trivy"
    "infracost"))

(define brew-casks
  '("iterm2" "the-unarchiver"
    "bruno"
    "dbgate"
    "claude"
    "claude-code"
    "signal"
    "omniwm"
    "mongodb-compass"
    "emacs-plus-app@master"
    "rectangle"
    "stats"
    "keepassxc"
    "raycast"
    "wezterm"))

(define (brew-output . args)
  "Run brew with @var{args}; return its stdout lines as a list."
  (let* ((port (apply open-pipe* OPEN_READ "brew" args))
         (lines (let loop
                  ((acc '()))
                  (let ((l (read-line port)))
                    (if (eof-object? l)
                        (reverse acc)
                        (loop (cons l acc)))))))
    (close-pipe port) lines))

(define (short-name name)
  (last (string-split name #\/)))

(define (missing items installed)
  (filter (lambda (i)
            (not (member (short-name i) installed))) items))

(define (brew-install! flags items)
  (unless (null? items)
    (log-info "Installing ~a" items)
    (let ((status (apply system* "brew" "install"
                         (append flags items))))
      (unless (zero? status)
        (log-error "brew install failed for ~a" items)
        (exit 1)))))

(define (install-brew-packages)
  (log-info "Ensuring Homebrew packages are installed")
  (unless (zero? (system* "brew" "--version"))
    (log-error "Homebrew not found, see https://brew.sh")
    (exit 1))
  (load-local-overrides '(cask-and-cons brew)
                        'brew-settings)
  (let ((tapped (brew-output "tap"))
        (formulae (brew-output "list" "--formula" "-1"))
        (casks (brew-output "list" "--cask" "-1")))
    (for-each (lambda (t)
                (unless (member t tapped)
                  (log-info "Tapping ~a" t)
                  (system* "brew" "tap" t))) brew-taps)
    (brew-install! '("-y")
                   (missing brew-formulae formulae))
    (brew-install! '("-y" "--cask")
                   (missing brew-casks casks)))
  (log-success "Homebrew packages are installed"))
