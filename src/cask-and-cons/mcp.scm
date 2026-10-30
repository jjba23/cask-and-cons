;;; cask-and-cons

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; SPDX-License-Identifier: MIT

;; MCP server configuration (Atlassian Rovo / Teamwork Graph) for the
;; GitHub Copilot JetBrains plugin, the Copilot CLI and ECA.

(define-module (cask-and-cons mcp)
  #:declarative? #f
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 match)
  #:use-module (cask-and-cons prelude)
  #:export (mcp-servers
            copilot-allowed-urls
            install-mcp-config))

(define mcp-servers
  (make-parameter
   ;;'(("atlassian" . "https://mcp.atlassian.com/v1/mcp"))
   '()
   ))

(define copilot-allowed-urls
  (make-parameter
   '("https://github.com"
     "https://api.github.com"
     "https://docs.github.com")))

(define (home)
  (or (getenv "HOME") "/tmp"))

(define (mkdir-p dir)
  "Create @var{dir} and any missing parents."
  (unless (file-exists? dir)
    (mkdir-p (dirname dir))
    (mkdir dir)))

;;; Minimal JSON emitter.  Objects are `(obj (key . value) ...)', arrays
;;; are plain lists, strings/#t/#f map directly.
(define (json-string s)
  (string-append "\"" (string-join (map (lambda (c)
                                          (case c
                                            ((#\") "\\\"")
                                            ((#\\) "\\\\")
                                            ((#\newline) "\\n")
                                            (else (string c))))
                                        (string->list s)) "") "\""))

(define (json x indent)
  (let ((pad (make-string (* 2 indent) #\space))
        (pad+ (make-string (* 2 (+ indent 1)) #\space)))
    (match x
      (('obj . pairs)
       (if (null? pairs)
           "{}"
           (string-append "{\n"
                          (string-join (map (lambda (p)
                                              (string-append pad+
                                                             (json-string (car p))
                                                             ": "
                                                             (json (cdr p)
                                                                   (+ indent 1))))
                                            pairs) ",\n")
                          "\n" pad "}")))
      ((? string?) (json-string x))
      (#t "true")
      (#f "false")
      ((? list?) (string-append "["
                                (string-join (map (lambda (i)
                                                    (json i indent)) x) ", ")
                                "]")))))

(define (servers-json key extra)
  "Build the document with servers under @var{key}; @var{extra} is a list of
additional (name . value) pairs merged into each server entry."
  (string-append
   (json `(obj (,key . (obj ,@(map (lambda (s)
                                      `(,(car s) . (obj ("type" . "http")
                                                        ("url" . ,(cdr s))
                                                        ,@extra)))
                                    (mcp-servers)))))
         0)
   "\n"))

(define (write-json! dir name contents)
  (mkdir-p dir)
  (install-config-file! #:name name #:dir dir #:contents contents))

(define (install-mcp-config)
  (log-info "Installing MCP configuration (JetBrains, Copilot CLI, ECA)")
  (load-local-overrides '(cask-and-cons mcp) 'mcp-settings)
  ;; GitHub Copilot for JetBrains
  (write-json! (format #f "~a/.config/github-copilot/intellij" (home))
               "mcp.json"
               (servers-json "servers" '()))
  ;; GitHub Copilot CLI
  (write-json! (format #f "~a/.copilot" (home))
               "mcp-config.json"
               (servers-json "mcpServers" '(("tools" . ("*")))))
  ;; Copilot CLI user settings.  Mouse support is off so the terminal keeps
  ;; selection and copy/paste to itself.
  (write-json! (format #f "~a/.copilot" (home))
               "settings.json"
               (string-append
                (json `(obj ("mouse" . #f)
                            ("allowedUrls" . ,(copilot-allowed-urls)))
                      0)
                "\n"))
  ;; ECA (remote servers only need a url)
  (write-json! (format #f "~a/.config/eca" (home))
               "config.json"
               (json `(obj ("mcpServers"
                            . (obj ,@(map (lambda (s)
                                            `(,(car s) . (obj ("url" . ,(cdr s)))))
                                          (mcp-servers)))))
                     0))
  (log-success "Installed MCP configuration"))
