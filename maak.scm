;;; cask-and-cons

;;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; SPDX-License-Identifier: MIT

;;; Commentary:
;;
;; This is cask-and-cons's Maak file, and it is the whole command line of the
;; project: `maak <task>' from the repository root (or from anywhere, once
;; `install-zsh' has put the `caco' shell function in place).  `maak' lists
;; the tasks, `maak install-git,install-zsh' chains them.
;;
;; Do not have maak yet?  Run `./bootstrap' (see the README); it installs the
;; Nix profile that carries maak.
;;
;; The exports are the task list.  Each task is one thin procedure over a
;; module in src/cask-and-cons/, which is where the work is done.

;; The modules live in ./src, which maak does not put on the load path by
;; itself.  This has to run before the module below is defined.
(eval-when (expand load eval)
  (add-to-load-path
   (string-append (dirname (or (current-filename) "./maak.scm")) "/src")))

(define-module (maak)
  #:declarative? #f
  #:use-module ((maak maak) #:hide (log-info log-error))
  #:use-module (ice-9 ftw)
  #:use-module (cask-and-cons prelude)
  #:use-module (cask-and-cons git)
  #:use-module (cask-and-cons gpg)
  #:use-module (cask-and-cons brew)
  #:use-module (cask-and-cons omniwm)
  #:use-module (cask-and-cons emacs)
  #:use-module (cask-and-cons zsh)
  #:use-module (cask-and-cons wezterm)
  #:use-module (cask-and-cons fonts)
  #:use-module (cask-and-cons macos)
  #:use-module (cask-and-cons skhd)
  #:use-module (cask-and-cons mcp)
  #:use-module (cask-and-cons kotlin-lsp)
  #:use-module (cask-and-cons ollama)
  #:use-module (cask-and-cons nix)
  #:use-module (cask-and-cons confluence)
  #:export (default
            compile-sources
            install-brew
            install-nix
            install-git
            install-gpg
            install-omniwm
            install-zsh
            install-wezterm
            install-macos
            install-skhd
            install-mcp
            install-confluence
            hr)
  ;; Tasks whose module function already has the task's name.
  #:re-export (install-emacs-bridge
               install-fontconfig
               install-jetbrains-fonts
               install-kotlin-lsp
               install-ollama
               sync-confluence
               login-confluence))

;; The Confluence module finds the repository through this, and writes it into
;; the launchd agent.  Maak runs from the directory of this file.
(setenv "CACO_DIR" (getcwd))

(define (default)
  "List the available tasks."
  (list-tasks))

(define (find-scm-files dir)
  "Recursively collect all @file{.scm} files under @var{dir}."
  (let ((acc '()))
    (ftw dir
         (lambda (filename statinfo flag)
           (when (and (eq? flag 'regular)
                      (string-suffix? ".scm" filename))
             (set! acc (cons filename acc)))
           #t))
    acc))

(define (compile-sources)
  "Byte-compile every .scm file under src/ with guild, warnings at -W3."
  (log-info "Compiling project sources")
  (for-each (lambda (file)
              (log-info "Compiling ~a" file)
              (unless (zero? (system* "guild" "compile" "-L" "src" "-W3" file))
                (log-error "Failed to compile ~a" file)
                (exit 1)))
            (find-scm-files "src"))
  (log-success "Compiled project sources"))

;; ====== Install targets ======

(define (install-brew)
  "Ensure the Homebrew taps, formulae and casks of brew.scm are installed."
  (install-brew-packages))

(define (install-nix)
  "Install the Nix profile (maak, sift and the rest, see flake.nix)."
  (install-nix-tools))

(define (install-git)
  "Install the Git configuration."
  (install-git-config))

(define (install-gpg)
  "Install the GnuPG configuration."
  (install-gpg-config))

(define (install-omniwm)
  "Install the OmniWM configuration."
  (install-omniwm-config))

(define (install-zsh)
  "Install the ZSH configuration (~/.zshrc and the pager keymap)."
  (install-zsh-config))

(define (install-wezterm)
  "Install the WezTerm configuration."
  (install-wezterm-config))

(define (install-macos)
  "Converge the macOS system preferences declared in macos.scm."
  (install-macos-settings))

(define (install-skhd)
  "Install the skhd configuration."
  (install-skhd-config))

(define (install-mcp)
  "Write the MCP server config for Copilot (JetBrains, CLI) and ECA."
  (install-mcp-config))

(define (install-confluence)
  "Install the launchd agent that runs sync-confluence weekly."
  (install-confluence-sync))

;; ====== Everything ======

(define install-tasks
  ;; Order matters: brew provides what the later tasks call.
  (list install-brew install-nix install-git install-gpg install-omniwm
        install-emacs-bridge install-zsh install-wezterm install-fontconfig
        install-jetbrains-fonts install-macos install-skhd install-mcp
        install-kotlin-lsp install-ollama install-confluence))

(define (hr)
  "Run every install-* task, in dependency order."
  (for-each (lambda (task) (task)) install-tasks))
