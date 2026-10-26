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
