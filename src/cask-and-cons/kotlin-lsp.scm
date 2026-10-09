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

(define-module (cask-and-cons kotlin-lsp)
  #:declarative? #t
  #:use-module (cask-and-cons prelude)
  #:use-module (cask-and-cons user-settings)
  #:export (kotlin-lsp))

(define (install-kotlin-lsp)
  "Install Kotlin Language Server (by JetBrains)"
  (let* ((release "263.6379.0")
         (download-dest "~/Downloads/kotlin-lsp-latest.tar.gz")
         (extract-dest "~/Downloads/kotlin-lsp-latest")
         (bin-dest "~/.local/bin/intellij-server"))
    (delete-file-recursively download-dest)
    (delete-file-recursively extract-dest)
    (delete-file-recursively bin-dest)
    ($ (list "curl --verbose"
             (~
              "https://download.jetbrains.com/language-server/kotlin-server/263.6379.0/kotlin-server-263.6379.0-aarch64.sit"
              "https://download-cdn.jetbrains.com/language-server/kotlin-server/~a/kotlin-server-~a.tar.gz"
              release release)
             (~ "--output ~a" download-dest))
       #:verbose? #t)
    (mkdir-p extract-dest)
    ($ (list "tar -xf" download-dest "-C" extract-dest)
       #:verbose? #t)
    ($ (list (~ "chmod +x ~a/kotlin-server-~a/bin/intellij-server"
                extract-dest release)))
    ($ (list "ln -s"
             (~ "~a/kotlin-server-~a/bin/intellij-server" extract-dest release)
             bin-dest))))
