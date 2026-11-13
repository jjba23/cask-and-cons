;;; cask-and-cons

;;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; SPDX-License-Identifier: MIT

(define-module (cask-and-cons git)
  #:declarative? #t
  #:use-module (cask-and-cons prelude)
  #:export (gitignore-global gitconfig-personal
                             gitconfig-work
                             gitconfig
                             install-git-config
                             git-config-dir
                             gitconfig-filename
                             gitconfig-personal-filename
                             gitconfig-work-filename
                             gitignore-global-filename))

(define gitignore-global
  `("bloop" ".bloop"
    ".metals"
    ".stack-work"
    "target"
    "metals.sbt"
    ".direnv"
    "dist-newstyle"))

(define gitconfig-personal
  `((user (name . "Josep Bigorra")
          (email . "jjbigorra@gmail.com")
          (signingkey . "83BC6E1C8726B8C297F8D16E24F46738CE114AF6"))))

(define gitconfig-work
  `((user (name . "Josep Bigorra")
          (email . "jjbigorra@gmail.com")
          (signingkey . "83BC6E1C8726B8C297F8D16E24F46738CE114AF6"))))

(define gitconfig
  `((core (editor . "emacsclient")
          (excludesfile . "~/.gitignore-global")
          ;; Every diff - `git diff', `git log -p', `git show' - is paged
          ;; through delta, which `maak install-brew' installs as the
          ;; `git-delta' formula (see brew.scm).  Same setting as on heks-linux.
          (pager . "delta"))
    (interactive
     ;; `git add -p' hands delta a patch, not a pager's input: without this it
     ;; pages a stream that is already formatted and the hunks come out plain.
     (diffFilter . "delta --color-only"))
    ;; n and N move between the sections of a diff instead of scrolling a
    ;; screen at a time.
    (delta (navigate . "true"))
    ;; zdiff3 keeps the common ancestor in view, which is what makes a
    ;; conflict readable rather than a wall of two versions.
    (merge (conflictStyle . "zdiff3"))
    (commit (gpgsign . "true"))
    (format (thread . "shallow"))
    (sendemail (thread . "no"))
    (pull (rebase . "false"))
    ("includeIf \"gitdir:~/Work/\"" ("  path" . "~/.gitconfig-work.ini"))
    ("includeIf \"gitdir:~/Hacking/\""
     ("  path" . "~/.gitconfig-personal.ini"))
    ("includeIf \"gitdir:~/Fork/\"" ("  path" . "~/.gitconfig-personal.ini"))
    ("includeIf \"gitdir:~/Scratch/\""
     ("  path" . "~/.gitconfig-personal.ini"))))

(define git-config-dir
  (make-parameter (format #f "~a"
                          (or (getenv "HOME") "/tmp"))))

(define gitconfig-filename
  (make-parameter ".gitconfig"))

(define gitconfig-personal-filename
  (make-parameter ".gitconfig-personal.ini"))

(define gitconfig-work-filename
  (make-parameter ".gitconfig-work.ini"))

(define gitignore-global-filename
  (make-parameter ".gitignore-global"))

(define (install-git-config)
  (log-info "Installing Git configuration ecosystem")
  (load-local-overrides '(cask-and-cons git)
                        'git-settings)
  (install-config-file! #:name (gitconfig-filename)
                        #:dir (git-config-dir)
                        #:contents (mk-rec-kv-conf-lines gitconfig
                                                         #:template spaced-equal-conf-pair))

  (install-config-file! #:name (gitconfig-personal-filename)
                        #:dir (git-config-dir)
                        #:contents (mk-rec-kv-conf-lines gitconfig-personal
                                                         #:template spaced-equal-conf-pair))

  (install-config-file! #:name (gitconfig-work-filename)
                        #:dir (git-config-dir)
                        #:contents (mk-rec-kv-conf-lines gitconfig-work
                                                         #:template spaced-equal-conf-pair))

  (install-config-file! #:name (gitignore-global-filename)
                        #:dir (git-config-dir)
                        #:contents (mk-lines gitignore-global))

  (log-success "Installed Git configuration ecosystem"))
