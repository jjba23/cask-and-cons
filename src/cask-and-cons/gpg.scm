;;; cask-and-cons

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; SPDX-License-Identifier: MIT

(define-module (cask-and-cons gpg)
  #:declarative? #t
  #:use-module (cask-and-cons prelude)
  #:use-module (cask-and-cons user-settings)
  #:export (gpg-agent-conf
            install-gpg-config
            gpg-config-dir
            gpg-agent-conf-filename))

(define gpg-agent-conf
  '("pinentry-program /opt/homebrew/bin/pinentry-mac"))

(define gpg-config-dir
  (make-parameter (format #f "~a/.gnupg"
                          (or (getenv "HOME") "/tmp"))))

(define gpg-agent-conf-filename
  (make-parameter "gpg-agent.conf"))

(define (install-gpg-config)
  (log-info "Installing GPG configuration")
  (load-local-overrides '(cask-and-cons gpg)
                        'gpg-settings)
  (install-config-file! #:name (gpg-agent-conf-filename)
                        #:dir (gpg-config-dir)
                        #:contents (mk-lines gpg-agent-conf))
  ;; Make the running agent pick up the new pinentry program.
  (system* "gpgconf" "--kill" "gpg-agent")
  (log-success "Installed GPG configuration"))
