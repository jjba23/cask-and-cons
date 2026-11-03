;;; cask-and-cons

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; SPDX-License-Identifier: MIT

;; Declarative local Markdown mirror of Confluence Cloud, refreshed weekly.
;;
;; `./caco sync-confluence' does one sync; `./caco install-confluence' writes
;; a launchd agent that runs it every week (Monday 09:00 by default; launchd
;; also runs missed jobs after wake).
;;
;; Credentials: store the API token once in the macOS keychain:
;;   security add-generic-password -a "$EMAIL" -s caco-confluence -w
;; (or export CONFLUENCE_API_TOKEN for manual runs).
;;
;; Override per machine in ~/.config/cask-and-cons/confluence-settings.scm:
;;   (confluence-base-url "https://acme.atlassian.net")
;;   (confluence-email "me@acme.com")
;;   (confluence-spaces '("ENG" "OPS"))

(define-module (cask-and-cons confluence)
  #:declarative? #f
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (srfi srfi-1)
  #:use-module (cask-and-cons prelude)
  #:export (confluence-base-url confluence-email confluence-spaces
                                confluence-destination
                                confluence-keychain-service
                                confluence-schedule
                                sync-confluence install-confluence-sync))

(define (home) (or (getenv "HOME") "/tmp"))

(define confluence-base-url (make-parameter "https://CHANGE-ME.atlassian.net"))
(define confluence-email (make-parameter "CHANGE-ME@example.com"))
;; Space keys to mirror; '() means every space you can see.
(define confluence-spaces (make-parameter '()))
(define confluence-destination
  (make-parameter (string-append (home) "/Hacking/confluence-mirror")))
(define confluence-keychain-service (make-parameter "caco-confluence"))
;; Weekday (0 = Sunday .. 6), hour, minute.
(define confluence-schedule (make-parameter '(1 9 0)))

(define label "org.jointhefreeworld.caco.confluence-sync")

;; The `caco' launcher exports CACO_DIR (the repo root).
(define (project-dir)
  (or (getenv "CACO_DIR") (getcwd)))

(define (script-path)
  (string-append (project-dir) "/src/cask-and-cons/confluence-sync.sh"))

(define (read-token)
  (or (let ((t (getenv "CONFLUENCE_API_TOKEN")))
        (and t (not (string-null? t)) t))
      (let* ((port (open-pipe* OPEN_READ "security" "find-generic-password"
                               "-s" (confluence-keychain-service) "-w"))
             (line (read-line port)))
        (close-pipe port)
        (and (string? line) (not (string-null? line)) line))))

(define (load-settings)
  (load-local-overrides '(cask-and-cons confluence) 'confluence-settings))

(define (sync-confluence)
  (load-settings)
  (let ((token (read-token)))
    (unless token
      (log-error "No API token: add it to the keychain (service ~a) or set CONFLUENCE_API_TOKEN"
                 (confluence-keychain-service))
      (exit 1))
    (when (string-contains (confluence-base-url) "CHANGE-ME")
      (log-error "Set confluence-base-url in ~~/.config/cask-and-cons/confluence-settings.scm")
      (exit 1))
    (setenv "CONFLUENCE_BASE_URL" (confluence-base-url))
    (setenv "CONFLUENCE_EMAIL" (confluence-email))
    (setenv "CONFLUENCE_TOKEN" token)
    (setenv "CONFLUENCE_SPACES" (string-join (confluence-spaces) " "))
    (setenv "CONFLUENCE_DEST" (confluence-destination))
    (log-info "Syncing Confluence to ~a" (confluence-destination))
    (unless (zero? (system* "bash" (script-path)))
      (log-error "Confluence sync failed")
      (exit 1))
    (log-success "Confluence synced")))

(define (plist)
  (let ((log-file (string-append (home) "/Library/Logs/caco-confluence.log"))
        (sched (confluence-schedule)))
    (string-append
     "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
     "<!-- auto-generated file! Regenerate with `./caco install-confluence`. -->\n"
     "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
     "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
     "<plist version=\"1.0\"><dict>\n"
     "  <key>Label</key><string>" label "</string>\n"
     "  <key>ProgramArguments</key><array>\n"
     "    <string>" (project-dir) "/caco</string>\n"
     "    <string>sync-confluence</string>\n"
     "  </array>\n"
     "  <key>EnvironmentVariables</key><dict>\n"
     "    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>\n"
     "  </dict>\n"
     "  <key>StartCalendarInterval</key><dict>\n"
     "    <key>Weekday</key><integer>" (number->string (first sched)) "</integer>\n"
     "    <key>Hour</key><integer>" (number->string (second sched)) "</integer>\n"
     "    <key>Minute</key><integer>" (number->string (third sched)) "</integer>\n"
     "  </dict>\n"
     "  <key>StandardOutPath</key><string>" log-file "</string>\n"
     "  <key>StandardErrorPath</key><string>" log-file "</string>\n"
     "</dict></plist>\n")))

(define (install-confluence-sync)
  (load-settings)
  (let ((dir (string-append (home) "/Library/LaunchAgents")))
    (install-config-file! #:name (string-append label ".plist")
                          #:dir dir
                          #:contents (plist))
    (let ((path (string-append dir "/" label ".plist")))
      (system* "launchctl" "unload" path)
      (system* "launchctl" "load" "-w" path)))
  (log-success "Installed weekly Confluence sync"))
