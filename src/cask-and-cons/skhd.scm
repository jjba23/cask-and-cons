;; Declarative global macOS hotkeys, served by skhd.
;;
;; `skhd-bindings' is plain data: a list of (KEYS COMMAND) pairs that get
;; serialized into ~/.config/skhd/skhdrc.  skhd needs Accessibility
;; permission (System Settings > Privacy & Security) on first start.
;;
;; Note: these are global, so they shadow the same chords inside every app
;; (e.g. Cmd+T for "new tab").

(define-module (cask-and-cons skhd)
  #:declarative? #f
  #:use-module (srfi srfi-1)
  #:use-module (cask-and-cons prelude)
  #:use-module (cask-and-cons user-settings)
  #:export (skhd-bindings skhd-config install-skhd-config
                          skhd-config-dir skhd-filename))

(define skhd-bindings
  (make-parameter
   '(("cmd - t" "open -a WezTerm")
     ("cmd - e" "/opt/homebrew/bin/emacsclient -c -n -a ''")
     ("cmd - b" "open -a Finder ~"))))

(define skhd-config-dir
  (make-parameter (format #f "~a/.config/skhd"
                          (or (getenv "HOME") "/tmp"))))

(define skhd-filename
  (make-parameter "skhdrc"))

(define (skhd-config)
  (string-append
   "# auto-generated file! Regenerate with `./caco install-skhd`.\n"
   "# Source of truth: src/cask-and-cons/skhd.scm\n\n"
   (string-join (map (lambda (b)
                       (format #f "~a : ~a" (first b) (second b)))
                     (skhd-bindings))
                "\n")
   "\n"))

(define (install-skhd-config)
  (log-info "Installing skhd configuration")
  (load-local-overrides '(cask-and-cons skhd) 'skhd-settings)
  (install-config-file! #:name (skhd-filename)
                        #:dir (skhd-config-dir)
                        #:contents (skhd-config))
  ;; Pick up the new config if the service is already running.
  (when (zero? (system* "which" "skhd"))
    (system* "skhd" "--reload"))
  (log-success "Installed skhd configuration"))
