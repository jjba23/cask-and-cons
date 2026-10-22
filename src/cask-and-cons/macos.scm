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

;; Declarative macOS system preferences (the `defaults' database).
;;
;; `macos-default-settings' is plain data: an alist of
;;   (DOMAIN (KEY . VALUE) ...)
;; where VALUE is a boolean, an exact integer, a real or a string, and picks
;; the matching `defaults write' type.  `install-macos-settings' compares each
;; key with the live value, writes only what differs, and restarts only the
;; processes (Dock, Finder, ...) whose domain actually changed.
;;
;; Only values that were explicitly set on the scanned machine are declared
;; here; everything else is left at the macOS default.  Not covered, on
;; purpose: Dock tiles (`persistent-apps' holds binary bookmarks) and the
;; Caps Lock -> Control modifier mapping (set per keyboard in System Settings).

(define-module (cask-and-cons macos)
  #:declarative? #t
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 textual-ports)
  #:use-module (cask-and-cons prelude)
  #:export (macos-settings
            macos-default-settings
            macos-domain-processes
            install-macos-settings))

(define macos-default-settings
  '(("com.apple.dock"
     ;; Dock behaviour
     (autohide . #t)
     (tilesize . 50)
     (show-recents . #f)
     (minimize-to-application . #t)
     ;; Hot corner, bottom right: 14 = Quick Note
     (wvous-br-corner . 14)
     (wvous-br-modifier . 0))

    ("com.apple.finder"
     (ShowExternalHardDrivesOnDesktop . #t)
     (ShowHardDrivesOnDesktop . #f)
     (ShowRemovableMediaOnDesktop . #t))

    ("NSGlobalDomain"
     (AppleInterfaceStyle . "Dark")
     (AppleAccentColor . 1)
     (AppleMiniaturizeOnDoubleClick . #f)
     (NSAutomaticCapitalizationEnabled . #t)
     (NSAutomaticPeriodSubstitutionEnabled . #t)
     (com.apple.swipescrolldirection . #f)  ; "natural" scrolling off
     (com.apple.sound.beep.flash . #f)
     (com.apple.springing.enabled . #t)
     (com.apple.springing.delay . 0.5)
     (com.apple.trackpad.forceClick . #t))

    ("com.apple.menuextra.clock"
     (ShowAMPM . #t)
     (ShowDate . 0)
     (ShowDayOfWeek . #t))

    ("com.apple.WindowManager"
     (AppWindowGroupingBehavior . 1)
     (EnableTiledWindowMargins . #f)
     (StandardHideWidgets . #f)
     (StageManagerHideWidgets . #f))

    ("com.apple.AppleMultitouchTrackpad"
     (Clicking . #t)
     (DragLock . #f)
     (Dragging . #f)
     (TrackpadThreeFingerDrag . #f)
     (TrackpadRightClick . #t)
     (TrackpadCornerSecondaryClick . 0))

    ("com.apple.driver.AppleBluetoothMultitouch.trackpad"
     (Clicking . #t)
     (DragLock . #f)
     (Dragging . #f)
     (TrackpadThreeFingerDrag . #f)
     (TrackpadRightClick . #t)
     (TrackpadCornerSecondaryClick . 0))))

;; Domain -> process to restart after one of its keys changed.
(define macos-domain-processes
  (make-parameter
   '(("com.apple.dock" . "Dock")
     ("com.apple.finder" . "Finder")
     ("com.apple.menuextra.clock" . "SystemUIServer")
     ("com.apple.WindowManager" . "Dock")
     ("NSGlobalDomain" . "Finder"))))

;; A parameter, so a machine-local override can replace or extend it:
;;   (macos-settings (append (macos-settings) '(("com.apple.dock" (tilesize . 36)))))
(define macos-settings
  (make-parameter macos-default-settings))

(define (value->flag value)
  "Return the @code{defaults write} type flag and argument for @var{value}."
  (cond
    ((boolean? value) (list "-bool" (if value "true" "false")))
    ((exact-integer? value) (list "-int" (number->string value)))
    ((real? value) (list "-float" (number->string value)))
    ((string? value) (list "-string" value))
    (else (error "Unsupported macOS default value:" value))))

(define (value->canonical value)
  "How @code{defaults read} prints @var{value}."
  (cond
    ((boolean? value) (if value "1" "0"))
    ((number? value) (number->string value))
    (else value)))

(define (read-default domain key)
  "Return the live value of @var{key} in @var{domain} as a string, or #f."
  (let* ((port (open-pipe* OPEN_READ "defaults" "read" domain key))
         (out (get-string-all port))
         (status (close-pipe port)))
    (and (zero? status)
         (string-trim-both out))))

(define (key->string key)
  (if (symbol? key) (symbol->string key) key))

(define (apply-default! domain key value)
  "Write one key.  Return #t when it changed, #f when already in place."
  (let* ((k (key->string key))
         (want (value->canonical value))
         (have (read-default domain k)))
    (cond
      ((equal? want have) #f)
      (else
       (log-info "~a ~a: ~a -> ~a" domain k (or have "<unset>") want)
       (let ((status (apply system* "defaults" "write" domain k
                            (value->flag value))))
         (unless (zero? status)
           (log-error "defaults write failed for ~a ~a" domain k))
         (zero? status))))))

(define (install-macos-settings)
  "Converge the macOS defaults database on @var{macos-settings}."
  (log-info "Installing macOS settings")
  (load-local-overrides '(cask-and-cons macos) 'macos-settings)
  (let* ((changed-domains
          (filter-map
           (lambda (entry)
             (let* ((domain (car entry))
                    (changed? (fold (lambda (kv acc)
                                      (or (apply-default! domain (car kv) (cdr kv))
                                          acc))
                                    #f (cdr entry))))
               (and changed? domain)))
           (macos-settings)))
         (processes (delete-duplicates
                     (filter-map (lambda (d)
                                   (assoc-ref (macos-domain-processes) d))
                                 changed-domains))))
    (for-each (lambda (p)
                (log-info "Restarting ~a" p)
                (system* "killall" p))
              processes)
    (if (null? changed-domains)
        (log-success "macOS settings already up to date")
        (log-success "Installed macOS settings (~a domain(s) changed)"
                     (length changed-domains)))))
