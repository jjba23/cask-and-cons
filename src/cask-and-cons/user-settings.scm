;;; cask-and-cons

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; SPDX-License-Identifier: MIT

;; Per-user, per-machine settings shared across cask-and-cons modules.
;; Individual modules can read/override these via `load-local-overrides'
;; (see `cask-and-cons prelude').

(define-module (cask-and-cons user-settings)
  #:use-module (srfi srfi-1)
  #:export (notes-directory global-theme theme-names theme-emacs-theme
                            theme-dark? theme-palette))

;; The one place that picks the colour scheme: a name from `theme-names'.
;; Emacs and WezTerm both follow it.  Change it here to retheme every consumer.
(define global-theme 'modus-operandi)

;; The palettes come from heks-linux (codeberg.org/jjba23/heks-linux), so a
;; theme looks the same on both systems.  Each row is
;;   (name emacs-theme dark? text background primary selection)
;; where `name' is what `global-theme' takes and `emacs-theme' is the theme
;; Heks Emacs loads for it (a few palettes borrow a close Emacs theme).
(define theme-definitions
  '((ef-melissa-light ef-melissa-light #f "#484431" "#fff6d8" "#efbf00" "#f5e9cb")
    (ef-dream ef-dream #t "#efd5c5" "#232025" "#675072" "#322f34")
    (ef-bio ef-bio #t "#dfefe6" "#111111" "#00552f" "#222522")
    (ef-cyprus ef-cyprus #f "#242521" "#fcf7ef" "#b3d19d" "#f0ece0")
    (ef-autumn ef-autumn #t "#dfcdcb" "#26211d" "#7a3b23" "#36322f")
    (ef-day ef-day #f "#3b3b3b" "#fefcf4" "#c06000" "#f4f0e0")
    (ef-kassio ef-kassio #f "#203235" "#f4f9fa" "#007a9a" "#e5eff1")
    (solarized-light solarized-light #f "#142a31" "#fdf6e3" "#f9a25a" "#eee8d5")
    (heavy-metal ef-tritanopia-dark #t "#ffe6d6" "#111111" "#b02930" "#222522")
    (everforest-dark everforest-hard-dark #t "#d3c6aa" "#272e33" "#a7c080" "#1e2326")
    (everforest-light everforest-hard-light #f "#272e33" "#fffbef" "#a7c080" "#eeeade")
    (gruvbox-dark gruvbox-dark-hard #t "#ebdbb2" "#1d2021" "#fe8019" "#282828")
    (gruvbox-light gruvbox-light-hard #f "#1d2021" "#ebdbb2" "#d65d0e" "#fbf1c7")
    (dracula dracula #t "#f8f8f2" "#282a36" "#bd93f9" "#44475a")
    (catppuccin-latte catppuccin-latte #f "#4c4f69" "#eff1f5" "#8839ef" "#e6e9ef")
    (catppuccin-mocha catppuccin-mocha #t "#cdd6f4" "#1e1e2e" "#cba6f7" "#181825")
    (modus-vivendi modus-vivendi #t "#ffffff" "#000000" "#feacd0" "#1e1e1e")
    (modus-operandi modus-operandi #f "#000000" "#ffffff" "#000000" "#bcbcbc")
    (modus-vivendi-tinted modus-vivendi-tinted #t "#ffffff" "#1d2021" "#feacd0" "#282a2b")
    (modus-operandi-tinted modus-operandi-tinted #f "#000000" "#fbf7ee" "#feacd0" "#f3ede2")
    (modus-vivendi-deuteranopia modus-vivendi-deuteranopia #t "#ffffff" "#000000" "#6495ed" "#1e1e1e")
    (modus-operandi-deuteranopia modus-operandi-deuteranopia #f "#000000" "#ffffff" "#0031a9" "#cbcbcb")
    (modus-vivendi-tritanopia modus-vivendi-tritanopia #t "#ffffff" "#000000" "#00bcff" "#1e1e1e")
    (modus-operandi-tritanopia modus-operandi-tritanopia #f "#000000" "#ffffff" "#005f88" "#cbcbcb")
    (kaolin-dark kaolin-dark #t "#e6e6e8" "#18181B" "#80bcb6" "#222225")
    (doom-tomorrow-night doom-tomorrow-night #t "#c5c8c6" "#1d1f21" "#de935f" "#161719")
    (doom-molokai doom-molokai #t "#dfdfdf" "#1c1e1f" "#fd971f" "#222323")
    (doom-one doom-one #t "#dfdfdf" "#282c34" "#c678dd" "#21242b")
    (doom-one-light doom-one-light #f "#383a42" "#fafafa" "#b751b6" "#f0f0f0")
    (solarized-dark solarized-dark #t "#839496" "#002b36" "#268bd2" "#073642")
    (nord nord #t "#eceff4" "#2e3440" "#88c0d0" "#3b4252")
    (tokyo-night tokyo-night #t "#c0caf5" "#1a1b26" "#7aa2f7" "#24283b")
    (rose-pine-moon rose-pine-moon #t "#e0def4" "#232136" "#ea9a97" "#2a283e")
    (rose-pine-dawn rose-pine-dawn #f "#575279" "#faf4ed" "#d7827e" "#fffaf3")
    (kanagawa kanagawa #t "#dcd7ba" "#1f1f28" "#7e9cd8" "#2a2a37")
    (ayu-dark ayu-dark #t "#e6e1cf" "#0f1419" "#ff9940" "#131721")
    (ayu-mirage ayu-grey #t "#cbccc6" "#212733" "#ffae57" "#242936")
    (ayu-light ayu-light #f "#5a6c75" "#fafafa" "#ff9940" "#f3f3f3")
    (golden-gate-light modus-operandi #f "#1d1d1f" "#f5f5f7" "#007aff" "#e5e5ea")
    (golden-gate-dark modus-vivendi #t "#f5f5f7" "#1e1e1e" "#0a84ff" "#2c2c2e")))

;; Optional hand-tuned ANSI colours, for themes where the terminal should not
;; fall back on WezTerm's defaults.
(define theme-ansi-overrides
  '((modus-operandi ("ansi" "#000000" "#a60000" "#006800" "#6f5500"
                     "#0031a9" "#721045" "#005e8b" "#a6a6a6")
                    ("brights" "#595959" "#d00000" "#008900" "#808000"
                     "#0000ff" "#dd22dd" "#008899" "#ffffff"))))

(define (theme-names)
  "Return every supported theme name."
  (map car theme-definitions))

(define (theme-definition name)
  (or (assq-ref theme-definitions name)
      (error "Unknown theme:" name (theme-names))))

(define (theme-emacs-theme name)
  "Return the Emacs theme symbol Heks Emacs should load for @var{name}."
  (car (theme-definition name)))

(define (theme-dark? name)
  "Return #t when theme @var{name} is dark."
  (cadr (theme-definition name)))

(define (theme-palette name)
  "Return the WezTerm colours of theme @var{name} as an association list."
  (let* ((d (cddr (theme-definition name)))
         (text (list-ref d 0))
         (bg (list-ref d 1))
         (primary (list-ref d 2))
         (selection (list-ref d 3)))
    (append `(("foreground" . ,text)
              ("background" . ,bg)
              ("cursor_bg" . ,primary)
              ("cursor_fg" . ,bg)
              ("selection_fg" . ,text)
              ("selection_bg" . ,selection))
            (or (assq-ref theme-ansi-overrides name) '()))))

;; Where the notes live.  One place for every consumer: the Emacs bridge sets
;; heks/notes-dir to it and the ZSH config exports it as $NOTES_DIR for the
;; `n' command.  $HOME is understood by both (the Emacs side turns it into ~).
(define notes-directory "$HOME/Hacking/private-notes")
