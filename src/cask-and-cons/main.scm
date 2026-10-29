;;; cask-and-cons

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; SPDX-License-Identifier: MIT

;; Scheme entrypoint for the cask-and-cons CLI.

(define-module (cask-and-cons main)
  #:declarative? #f
  #:use-module (ice-9 match)
  #:use-module (ice-9 ftw)
  #:use-module (cask-and-cons prelude)
  #:use-module (cask-and-cons git)
  #:use-module (cask-and-cons gpg)
  #:use-module (cask-and-cons brew)
  #:use-module (cask-and-cons omniwm)
  #:use-module (cask-and-cons emacs)
  #:use-module (cask-and-cons zsh)
  #:use-module (cask-and-cons wezterm)
  #:use-module (cask-and-cons macos)
  #:use-module (cask-and-cons skhd)
  #:use-module (cask-and-cons mcp)
  #:export (main))

(define (find-scm-files dir)
  "Recursively collect all @file{.scm} files under @var{dir}."
  (let ((acc '()))
    (ftw dir
         (lambda (filename statinfo flag)
           (when (and (eq? flag
                           'regular)
                      (string-suffix? ".scm" filename))
             (set! acc
                   (cons filename acc))) #t)) acc))

(define (compile)
  "Compile all project source code."
  (log-info "Compiling project sources")
  (let ((files (find-scm-files "src")))
    (for-each (lambda (file)
                (log-info "Compiling ~a" file)
                (let ((status (system* "guild"
                                       "compile"
                                       "-L"
                                       "src"
                                       "-W3"
                                       file)))
                  (unless (zero? status)
                    (log-error "Failed to compile ~a" file)
                    (exit 1)))) files))
  (log-success "Compiled project sources"))

;; name -> thunk taking the remaining task args.  Install targets are plain
;; tasks named "install-<target>" (e.g. "install-git"), so adding a new
;; dotfile module just means adding one more entry here.
(define %tasks
  `((compile unquote
             (lambda (args)
               (compile)))
    (install-git unquote
                 (lambda (args)
                   (install-git-config)))
    (install-gpg unquote
                 (lambda (args)
                   (install-gpg-config)))
    (install-brew unquote
                  (lambda (args)
                    (install-brew-packages)))
    (install-omniwm unquote
                    (lambda (args)
                      (install-omniwm-config)))
    (install-emacs-bridge unquote
                          (lambda (args)
                            (install-emacs-bridge)))
    (install-zsh unquote
                 (lambda (args)
                   (install-zsh-config)))
    (install-wezterm unquote
                     (lambda (args)
                       (install-wezterm-config)))
    (install-macos unquote
                    (lambda (args)
                      (install-macos-settings)))
    (install-skhd unquote
                  (lambda (args)
                    (install-skhd-config)))
    (install-mcp unquote
                 (lambda (args)
                   (install-mcp-config)))
    (hr unquote
        (lambda (args)
          ;; Run every install-* task, in the order listed above.
          (for-each (lambda (name)
                      (when (string-prefix? "install-"
                                            (symbol->string name))
                        (dispatch (symbol->string name)
                                  '()))) (map car %tasks))))
    (list unquote
          (lambda (args)
            (log-info "Available tasks: ~a"
                      (map car %tasks))))))

(define (dispatch task-name task-args)
  (let* ((task-name (string->symbol (if (string=? task-name "--list") "list"
                                        task-name)))
         (entry (assq task-name %tasks)))
    (if entry
        (begin
          (log-info "Running task ~a ~a" task-name task-args)
          ((cdr entry)
           task-args)
          (log-success "Task ~a finished" task-name))
        (begin
          (log-error "Unknown task: ~a" task-name)
          (log-info "Available tasks: ~a"
                    (map car %tasks))
          (exit 1)))))

(define (run-chain task-names rest)
  "Run each comma-separated task in @var{task-names} in order, with no args.
Tasks that require their own arguments are not supported in a chain and
must be run on their own."
  (unless (null? rest)
    (log-warning
     "Ignoring extra arguments ~a when running a chained task list" rest))
  (for-each (lambda (task-name)
              (dispatch task-name
                        '())) task-names))

(define (main args)
  (match (cdr args)
     ;drop argv[0] (script path)
    ((task-arg . rest) (let ((task-names (string-split task-arg #\,)))
                         (if (> (length task-names) 1)
                             (run-chain task-names rest)
                             (dispatch task-arg rest))))
    (() (log-error "No task given.")
     (log-info "Usage: ~a <task> [args...]"
               (car args))
     (log-info "Usage: ~a <task1>,<task2>,... (chain tasks with no args)"
               (car args))
     (log-info "Available tasks: ~a"
               (map car %tasks))
     (exit 1))))
