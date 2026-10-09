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

(define-module (cask-and-cons omniwm)
  #:declarative? #t
  #:use-module (cask-and-cons prelude)
  #:use-module (cask-and-cons user-settings)
  #:export (omniwm-config
                             install-omniwm-config
                             omniwm-config-dir
                             omniwm-filename))



(define omniwm-config
  "
schemaVersion = 4

[borders]
width = 2.0
color = { red = 0.1846, green = 1.0, blue = 0.8793, alpha = 0.7 }
")

(define omniwm-config-dir
  (make-parameter (format #f "~a/.config/omniwm"
                          (or (getenv "HOME") "/tmp"))))

(define omniwm-filename
  (make-parameter "settings.toml"))

(define (install-omniwm-config)
  (log-info "Installing OmniWM configuration")
  (load-local-overrides '(cask-and-cons omniwm) 'omniwm-settings)
  (install-config-file! #:name (omniwm-filename)
                        #:dir (omniwm-config-dir)
                        #:contents omniwm-config)

  (log-success "Installed OmniWM configuration"))
