;;; cask-and-cons

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; SPDX-License-Identifier: MIT

(define-module (cask-and-cons nix)
  #:declarative? #f
  #:use-module (cask-and-cons prelude)
  #:export (install-nix-tools))

(define (flake-dir)
  "The repository root, where flake.nix lives (two levels above this module)."
  (dirname (dirname (dirname (search-path %load-path "cask-and-cons/nix.scm")))))

(define (nix-bin)
  "The nix executable: the one on PATH, else the default multi-user install."
  (or (search-path (string-split (or (getenv "PATH") "") #\:) "nix")
      "/nix/var/nix/profiles/default/bin/nix"))

(define (run! . argv)
  (log-info "$ ~{~a~^ ~}" argv)
  (let ((status (apply system* argv)))
    (unless (zero? status)
      (log-error "Command failed (status ~a): ~{~a~^ ~}" status argv)
      (error "nix: command failed" argv))))

(define (install-nix-tools)
  "Install the programs of the nix-jointhefreeworld flake (maak, sift, veritas
and the rest, see flake.nix) into the user's Nix profile as one entry,
@code{caco-tools}.  Running it again replaces the entry, which is how the
pinned versions are updated."
  (let* ((nix (nix-bin))
         (flags '("--extra-experimental-features" "nix-command flakes"))
         (ref (string-append "path:" (flake-dir))))
    ;; `path:' so that flake.nix need not be tracked by git.
    (apply system* nix (append flags '("profile" "remove" "caco-tools")))
    (apply run! nix (append flags
                            (list "profile" "install"
                                  (string-append ref "#caco-tools"))))
    (log-success "Nix tools installed in the user profile")))
