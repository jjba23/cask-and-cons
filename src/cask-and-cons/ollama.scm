;;; cask-and-cons

;;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; SPDX-License-Identifier: MIT

;;; Declarative Ollama setup: runs the Homebrew service and pulls the
;;; models listed in @code{ollama-models}.  The @code{ollama} formula itself
;;; is installed by the brew module.

(define-module (cask-and-cons ollama)
  #:declarative? #f
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (srfi srfi-1)
  #:use-module (cask-and-cons prelude)
  #:use-module (cask-and-cons user-settings)
  #:export (ollama-models install-ollama))

(define ollama-models
  ;; Sized for a 16 GB Apple Silicon laptop (~5 GB each at Q4).  qwen3 has
  ;; solid tool calling, which ECA's agent needs; qwen2.5-coder is the
  ;; stronger pure code model.  Bigger (14b, ~9 GB) fits but leaves little
  ;; room for the context window.
  '("qwen3:8b"
    "qwen2.5-coder:7b"))

(define (ollama-ready?)
  "True when the Ollama server answers on its local API."
  (zero? (system* "curl" "--silent" "--fail" "--max-time" "2"
                  "http://localhost:11434/api/version" "--output" "/dev/null")))

(define (wait-for-ollama! tries)
  (cond ((ollama-ready?) #t)
        ((zero? tries)
         (log-error "Ollama server did not come up on localhost:11434")
         (exit 1))
        (else (sleep 1)
              (wait-for-ollama! (- tries 1)))))

(define (pulled-models)
  "Names of the models already present locally."
  (let* ((port (open-pipe* OPEN_READ "ollama" "list"))
         (lines (let loop ((acc '()))
                  (let ((l (read-line port)))
                    (if (eof-object? l)
                      (reverse acc)
                      (loop (cons l acc)))))))
    (close-pipe port)
    ;; Skip the header row; the model name is the first column.
    (if (null? lines)
      '()
      (map (lambda (l) (car (string-tokenize l)))
           (filter (lambda (l) (not (string-null? (string-trim-both l))))
                   (cdr lines))))))

(define (install-ollama)
  "Start the Ollama service and pull every model in @code{ollama-models}."
  (log-info "Ensuring Ollama is running and models are pulled")
  (unless (zero? (system* "ollama" "--version"))
    (log-error "ollama not found; run install-brew first")
    (exit 1))
  (load-local-overrides '(cask-and-cons ollama) 'ollama-settings)
  (unless (ollama-ready?)
    (log-info "Starting the Ollama service")
    (system* "brew" "services" "start" "ollama"))
  (wait-for-ollama! 30)
  (let ((have (pulled-models)))
    (for-each (lambda (model)
                ;; Untagged names resolve to ":latest".
                (if (member (if (string-index model #\:)
                              model
                              (string-append model ":latest"))
                            have)
                  (log-info "Model ~a already pulled" model)
                  (begin
                    (log-info "Pulling ~a" model)
                    (unless (zero? (system* "ollama" "pull" model))
                      (log-error "ollama pull failed for ~a" model)
                      (exit 1)))))
              ollama-models))
  (log-success "Ollama is running with models ~a" ollama-models))
