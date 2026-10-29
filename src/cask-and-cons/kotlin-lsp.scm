;;; cask-and-cons

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; SPDX-License-Identifier: MIT

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
