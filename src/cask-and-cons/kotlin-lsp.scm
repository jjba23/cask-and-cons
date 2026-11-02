;;; cask-and-cons

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; SPDX-License-Identifier: MIT

(define-module (cask-and-cons kotlin-lsp)
  #:declarative? #f
  #:use-module (ice-9 format)
  #:use-module (cask-and-cons prelude)
  #:export (kotlin-lsp-release
            install-kotlin-lsp))

(define kotlin-lsp-release
  ;; JetBrains Kotlin Language Server release; bump this to update.
  "263.7084.0")

(define (home-path . parts)
  "Return an absolute path made of the user's home directory and @var{parts}."
  (string-join (cons (getenv "HOME") parts) "/"))

(define (run! . argv)
  "Run the program @var{argv} (no shell involved), raising an error when it
exits with a non-zero status."
  (log-info "$ ~{~a~^ ~}" argv)
  (let ((status (apply system* argv)))
    (unless (zero? status)
      (log-error "Command failed (status ~a): ~{~a~^ ~}" status argv)
      (error "kotlin-lsp: command failed" argv))))

(define (install-kotlin-lsp)
  "Download and install the Kotlin Language Server (by JetBrains) at
@code{kotlin-lsp-release}, and symlink its @code{intellij-server} binary to
@file{~/.local/bin/intellij-server}."
  (let* ((release kotlin-lsp-release)
         (url (format #f "https://download.jetbrains.com/language-server/kotlin-server/~a/kotlin-server-~a-aarch64.sit"
                      release release))
         (download-dest (home-path "Downloads" "kotlin-lsp-latest.zip"))
         (extract-dest (home-path "Downloads" "kotlin-lsp-latest"))
         (server (string-append extract-dest "/kotlin-server-" release
                                "/bin/intellij-server"))
         (bin-dir (home-path ".local" "bin"))
         (bin-dest (string-append bin-dir "/intellij-server")))
    (log-info "Installing Kotlin LSP ~a" release)
    (run! "rm" "-rf" download-dest extract-dest bin-dest)
    (run! "mkdir" "-p" extract-dest bin-dir)
    (run! "curl" "--fail" "--location" "--silent" "--show-error"
          url "--output" download-dest)
    (run! "unzip" "-q" download-dest "-d" extract-dest)
    (run! "chmod" "+x" server)
    (run! "ln" "-s" server bin-dest)
    (log-success "Kotlin LSP ~a installed at ~a" release bin-dest)))
