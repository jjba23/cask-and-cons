;;; cask-and-cons

;;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; SPDX-License-Identifier: MIT

;;; Commentary:
;;
;; Renders an iTerm2 Dynamic Profile,
;; ~/Library/Application Support/iTerm2/DynamicProfiles/cask-and-cons.json,
;; and makes it iTerm2's default profile.
;;
;; The colours come from `global-theme' (see (cask-and-cons user-settings)), the
;; same theme Heks Emacs loads, and the font is `font-mono', so the terminal and
;; the editor agree.  The other things the README used to ask you to click
;; through are values here too: Option as Esc+ (Meta), 100k lines of scrollback,
;; transparency and blur.  iTerm2 reloads Dynamic Profiles on its own.

(define-module (cask-and-cons iterm)
  #:declarative? #f
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 format)
  #:use-module (cask-and-cons prelude)
  #:use-module (cask-and-cons user-settings)
  #:export (iterm-palette iterm-font-family iterm-font-size
                          iterm-window-opacity iterm-window-blur
                          iterm-scrollback-lines iterm-profile-name
                          iterm-profile-guid iterm-config-dir
                          iterm-config-filename iterm-ansi-colors
                          iterm-color iterm-profile iterm-config
                          install-iterm-config))

(define iterm-palette
  (make-parameter (theme-palette global-theme)))

(define iterm-font-family
  (make-parameter font-mono-postscript-name))

(define iterm-font-size
  (make-parameter 12))

;;; 1.0 is opaque.  iTerm2 stores the inverse, "Transparency".
(define iterm-window-opacity
  (make-parameter 0.88))

;;; Blur radius, 0 to 30.
(define iterm-window-blur
  (make-parameter 20))

(define iterm-scrollback-lines
  (make-parameter 100000))

(define iterm-profile-name
  (make-parameter "Cask and Cons"))

;;; Fixed, so that regenerating the file updates the same profile.
(define iterm-profile-guid
  (make-parameter "6C0A5C0B-CA5C-4C0D-9C0D-CA5CA4DC0450"))

(define iterm-config-dir
  (make-parameter (format #f "~a/Library/Application Support/iTerm2/DynamicProfiles"
                          (or (getenv "HOME") "/tmp"))))

(define iterm-config-filename
  (make-parameter "cask-and-cons.json"))

;;; Fallback ANSI colours (normal, then bright) for themes without hand-tuned
;;; ones in `theme-ansi-overrides'.
(define default-dark-ansi
  '("#000000" "#cd3131" "#0dbc79" "#e5e510" "#2472c8" "#bc3fbc" "#11a8cd" "#e5e5e5"
    "#666666" "#f14c4c" "#23d18b" "#f5f543" "#3b8eea" "#d670d6" "#29b8db" "#ffffff"))

(define default-light-ansi
  '("#000000" "#a60000" "#006800" "#6f5500" "#0031a9" "#721045" "#005e8b" "#a6a6a6"
    "#595959" "#d00000" "#008900" "#808000" "#0000ff" "#dd22dd" "#008899" "#ffffff"))

(define (iterm-ansi-colors)
  "Return the 16 ANSI colours as hex strings: the theme's, else a default."
  (let ((ansi (assoc "ansi" (iterm-palette)))
        (brights (assoc "brights" (iterm-palette))))
    (if (and ansi brights)
        (append (cdr ansi) (cdr brights))
        (if (theme-dark? global-theme)
            default-dark-ansi
            default-light-ansi))))

(define (hex->components hex)
  (map (lambda (i)
         (/ (string->number (substring hex i (+ i 2)) 16) 255.))
       '(1 3 5)))

(define (iterm-color hex)
  "Return the JSON object iTerm2 wants for the colour @var{hex} (#rrggbb)."
  (let ((c (hex->components hex)))
    (format #f "{\"Red Component\": ~a, \"Green Component\": ~a, \"Blue Component\": ~a, \"Alpha Component\": 1, \"Color Space\": \"sRGB\"}"
            (first c) (second c) (third c))))

(define (json-string s)
  (string-append "\"" s "\""))

(define (palette-ref key)
  (or (assoc-ref (iterm-palette) key)
    (error "iterm: palette has no" key)))

(define (iterm-profile)
  "Return the profile as an association list of (key . json-text)."
  (append
   `(("Name" . ,(json-string (iterm-profile-name)))
     ("Guid" . ,(json-string (iterm-profile-guid)))
     ("Normal Font" . ,(json-string (format #f "~a ~a" (iterm-font-family)
                                            (iterm-font-size))))
     ("Use Non-ASCII Font" . "false")
     ("Option Key Sends" . "2")
     ("Right Option Key Sends" . "2")
     ("Scrollback Lines" . ,(number->string (iterm-scrollback-lines)))
     ("Unlimited Scrollback" . "false")
     ("Transparency" . ,(number->string (- 1. (iterm-window-opacity))))
     ("Blur" . ,(if (> (iterm-window-blur) 0) "true" "false"))
     ("Blur Radius" . ,(number->string (iterm-window-blur)))
     ("Foreground Color" . ,(iterm-color (palette-ref "foreground")))
     ("Background Color" . ,(iterm-color (palette-ref "background")))
     ("Cursor Color" . ,(iterm-color (palette-ref "cursor_bg")))
     ("Cursor Text Color" . ,(iterm-color (palette-ref "cursor_fg")))
     ("Selected Text Color" . ,(iterm-color (palette-ref "selection_fg")))
     ("Selection Color" . ,(iterm-color (palette-ref "selection_bg"))))
   (map (lambda (hex i)
          (cons (format #f "Ansi ~a Color" i) (iterm-color hex)))
        (iterm-ansi-colors)
        (iota 16))))

(define (iterm-config)
  "Return the complete Dynamic Profiles JSON document as a string."
  (string-append
   "{\n  \"Profiles\": [\n    {\n"
   (string-join (map (lambda (kv)
                       (format #f "      ~a: ~a" (json-string (car kv)) (cdr kv)))
                     (iterm-profile))
                ",\n")
   "\n    }\n  ]\n}\n"))

(define (install-iterm-config)
  "Write the Dynamic Profile and make it iTerm2's default profile.

A machine-specific override may live in
@file{$XDG_CONFIG_HOME/cask-and-cons/iterm-settings.scm}."
  (log-info "Installing iTerm2 profile")
  (load-local-overrides '(cask-and-cons iterm) 'iterm-settings)
  (system* "mkdir" "-p" (iterm-config-dir))
  (install-config-file! #:name (iterm-config-filename)
                        #:dir (iterm-config-dir)
                        #:contents (iterm-config))
  (system* "defaults" "write" "com.googlecode.iterm2" "Default Bookmark Guid"
           "-string" (iterm-profile-guid))
  (log-success "Installed iTerm2 profile (restart iTerm2 if it is running)"))
