;;; cask-and-cons

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; SPDX-License-Identifier: MIT

(define-module (cask-and-cons prelude)
  #:declarative? #f
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 format)
  #:use-module (ice-9 string-fun)
  #:use-module (ice-9 textual-ports)
  #:use-module (ice-9 format)
  #:use-module (srfi srfi-19)
  #:export (G_ setup-i18n
               syscall
               flatten-list
               spaced-conf-pair
               mk-lines
               mk-kv-conf-lines
               serialize-rec-conf-item
               mk-rec-kv-conf-lines
               spaced-equal-conf-pair
               equal-conf-pair
               equal-conf-quote-value-pair
               load-local-overrides
               css-conf-pair
               install-config-file!
               nix-profile-install
               mk-css-conf-lines
               log-error
               log-warning
               log-info
               log-success))

(define* (syscall cmd
                  #:key (silent? #f))
  "Execute the system command @var{cmd} via an input pipe and return its stdout.
If @var{silent?} is true, the output is also printed to the current output port.

@example
(syscall \"echo 'hello'\")
@result{} \"hello
\"
@end example"
  (let* ((process (open-input-pipe cmd))
         (process-output (get-string-all process)))
    (close-pipe process)
    (unless silent?
      (display process-output)) process-output))

(define (mk-lines items)
  "Join a list of @var{items} into a single string, appending a newline to each item.

@example
(mk-lines '(\"foo\" \"bar\"))
@result{} \"foo
bar
\"
@end example"
  (with-output-to-string (lambda ()
                           (for-each (lambda (x)
                                       (format #t "~a\n" x)) items))))

(define* (mk-css-conf-lines pairs)
  "Format an association list of @var{pairs} into a CSS ruleset string.

@example
(mk-css-conf-lines '((body (color . \"black\") (margin . 0))))
@result{} \"body {
  color: black;
  margin: 0;
}
\"
@end example"
  (with-output-to-string (lambda ()
                           (for-each (lambda (x)
                                       (format #t "~a {\n"
                                               (car x))
                                       (display (mk-kv-conf-lines (cdr x)
                                                 #:template css-conf-pair))
                                       (display "}\n\n")) pairs))))

(define* (mk-kv-conf-lines pairs
                           #:key (template "~a=~a\n"))
  "Format an association list of @var{pairs} into configuration lines using @var{template}.

@example
(mk-kv-conf-lines '((host . \"localhost\") (port . 80)))
@result{} \"host=localhost
port=80
\"
@end example"
  (with-output-to-string (lambda ()
                           (for-each (lambda (x)
                                       (cond
                                         ((pair? x)
                                          (format #t template
                                                  (car x)
                                                  (cdr x)))
                                         (else (format #t "~a" x)))) pairs))))

(define (serialize-rec-conf-item template item)
  "Serialize a single configuration @var{item} using @var{template} to the current output port.
If the item's value is a list, it formats the key as an INI-style section header.

@example
(with-output-to-string
  (lambda () (serialize-rec-conf-item \"~a=~a
\" '(port . 80))))
@result{} \"port=80
\"
@end example"
  (cond
    ((list? (cdr item))
     (cond
       ((string? (car item))
        (display (string-append "\n["
                                (car item) "]\n")))
       (else (display (string-append "\n["
                                     (symbol->string (car item)) "]\n"))))
     (display (mk-rec-kv-conf-lines (cdr item)
                                    #:template template)))
    (else (format #t template
                  (car item)
                  (cdr item)))))

(define* (mk-rec-kv-conf-lines pairs
                               #:key (template equal-conf-pair))
  "Recursively format nested configuration @var{pairs} into a string using @var{template}.
This handles both top-level key-values and nested blocks as INI-style sections.

@example
(mk-rec-kv-conf-lines '((settings (port . 8080))) #:template \"~a=~a
\")
@result{} \"
[settings]
port=8080
\"
@end example"
  (with-output-to-string (lambda ()
                           (for-each (lambda (item)
                                       (serialize-rec-conf-item template item))
                                     pairs))))

(define spaced-equal-conf-pair
  "~a = ~a\n")

(define equal-conf-pair
  "~a=~a\n")

(define equal-conf-quote-value-pair
  "~a=\"~a\"\n")

(define spaced-conf-pair
  "~a ~a\n")

(define css-conf-pair
  "  ~a: ~a;\n")

(define (nix-profile-install x)
  "Install the Nix package specified by the attribute path @var{x} via system call.

@example
(nix-profile-install \"nixpkgs.tmux\")
@end example"
  (syscall (format #f "nix-env -iA ~a" x)))

(define (flatten-list xs)
  "Recursively flatten a nested list structure @var{xs} into a single flat list.

@example
(flatten-list '(1 (2 (3 4)) 5))
@result{} (1 2 3 4 5)
@end example"
  (cond
    ((null? xs)
     '())
    ((pair? xs)
     (append (flatten-list (car xs))
             (flatten-list (cdr xs))))
    (else (list xs))))

(define* (install-config-file! #:key name dir contents
                               (perms 420))
  "Write @var{contents} to a file named @var{name} inside directory @var{dir}.
If @var{dir} does not exist, it will be created automatically.

@example
(install-config-file! #:name \"config.toml\"
                      #:dir \"/etc/myapp\"
                      #:contents \"[settings]
port = 8080\")
@end example"
  (unless (file-exists? dir)
    (begin
      (log-info "Creating directory: ~a" dir)
      (mkdir dir)))
  (let* ((path-to-file (format #f "~a/~a" dir name))
         (dist-path-to-file (format #f "dist/~a-~a"
                                    (string-replace-substring dir "/" "-")
                                    name))
         (file-port (open-output-file path-to-file))
         ;; (dist-file-port (open-output-file dist-path-to-file))
         )
    (log-info "Writing config to file: ~a" path-to-file)
    (set-port-encoding! file-port "UTF-8")
    (display contents file-port)
    (close-output-port file-port)
    ;; Apply file permissions (e.g., #o644, #o755, #o600)
    (chmod path-to-file perms)
    ;; write to ./dist/
    ;; (set-port-encoding! dist-file-port "UTF-8")
    ;; (display contents dist-file-port)
    ;; (close-output-port dist-file-port)
    ))

(define (get-config-dir xdg-config)
  (if (and xdg-config
           (not (string=? xdg-config "")))
      (begin
        (log-info "load-local-overrides: Using $XDG_CONFIG_HOME: ~a"
                  xdg-config) xdg-config)
      (let ((home (getenv "HOME")))
        (if home
            (begin
              (log-info
               "load-local-overrides: $XDG_CONFIG_HOME empty/unset, falling back to $HOME/.config")
              (format #f "~a/.config" home))

            (begin
              (log-info
               "load-local-overrides: Warning - Neither $XDG_CONFIG_HOME nor $HOME is defined.")
              #f)))))

(define (load-local-overrides module-name profile-name)
  "Dynamically load a machine-specific configuration file within a target module.

Look for an optional configuration file at the path
@file{$XDG_CONFIG_HOME/cask-and-cons/@var{profile-name}.scm}, defaulting to
@file{~/.config/cask-and-cons/@var{profile-name}.scm} if @env{XDG_CONFIG_HOME} is
not set or empty.  If the file exists, temporarily switch the active module
context to @var{module-name} using @code{save-module-excursion} before
executing @code{load}.

This ensures that the localized configuration script evaluates within the
namespace where the module's parameters and internal definitions are bound,
preventing unbound variable errors.

@example
(load-local-overrides '(cask-and-cons waybar) 'waybar-settings)
@end example"
  (log-info
   "load-local-overrides: Attempting override resolution for module ~a with profile '~a'"
   module-name profile-name)
  (let* ((xdg-config (getenv "XDG_CONFIG_HOME"))
         (config-dir (get-config-dir xdg-config)))
    (if config-dir
        (let ((local-file (format #f "~a/cask-and-cons/~a.scm" config-dir
                                  profile-name)))
          (log-info "load-local-overrides: Checking for override file at: ~a"
                    local-file)
          (if (file-exists? local-file)
              (begin
                (log-info
                 "load-local-overrides: Override file found (~a). Entering module excursion into ~a..."
                 local-file module-name)
                (save-module-excursion (lambda ()
                                         (set-current-module (resolve-module
                                                              module-name))
                                         (log-info

                                          "load-local-overrides: Loading ~a into ~a scope..."
                                          local-file module-name)
                                         (load local-file)
                                         (log-info
                                          "load-local-overrides: Successfully loaded ~a"
                                          local-file))))
              (log-info
               "load-local-overrides: No override file found at ~a. Skipping."
               local-file)))
        (log-info
         "load-local-overrides: Could not resolve a config directory. Skipping."))))

(define (log--timestamp)
  (date->string (current-date) "~H:~M:~S"))

(define (log--emit port color label fmt args)
  (let ((msg (apply format #f fmt args)))
    (format port
            "\x1b[~am[~a] ~a: ~a\x1b[0m~%"
            color
            (log--timestamp)
            label
            msg)))

(define (log-error fmt . args)
  (log--emit (current-error-port) 31 "ERROR" fmt args))

(define (log-warning fmt . args)
  (log--emit (current-error-port) 33 "WARN" fmt args))

(define (log-info fmt . args)
  (log--emit (current-output-port) 36 "INFO" fmt args))

(define (log-success fmt . args)
  (log--emit (current-output-port) 32 "OK" fmt args))
