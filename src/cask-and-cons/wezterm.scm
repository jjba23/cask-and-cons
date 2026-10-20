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

;; Renders ~/.config/wezterm/wezterm.lua.
;;
;; WezTerm is configured in Lua, so this module generates a Lua file: the
;; settings, the application list and the key bindings are Scheme data rendered
;; by `serialize-wezterm-value' and `serialize-wezterm-key', wrapped by a fixed
;; block of Lua (`wezterm-lua-runtime') that turns them into a configuration.
;; Keeping the mechanism in one visible place is the point of the split: the
;; parts a user changes are data, and the part that implements the policy never
;; has to be re-read.
;;
;; The key bindings are the Emacs ones, and that is what replaces the manual
;; iTerm2 setup described in the README: instead of telling iTerm2 by hand that
;; Option should behave like Meta, every chord WezTerm claims here is *guarded*.
;; WezTerm hands each action a callback, and the callback can ask the pane which
;; process is in front of it, so when the foreground process is one of
;; `wezterm-yield-apps' - Emacs above all, but also `less' and every full-screen
;; program - the chord is re-sent to that application untouched and the terminal
;; stays out of the way.  C-x is the clearest example: at a shell prompt it is the
;; prefix of the window commands, and inside Emacs it is Emacs's own C-x.
;;
;; Two rules come from the pager, and are the reason the terminal claims so few
;; chords: `less' reads its Emacs keymap from the shared lesskey file installed
;; with the ZSH configuration (C-v is forw-screen, M-v is back-screen), so C-v
;; and M-v are never bound here, and the scrollback lives on S-PageUp and
;; S-PageDown instead.  C-c is never bound either: it is Emacs's leader key, but
;; in a terminal it is also the interrupt signal.
;;
;; The prefix table maps Emacs's window commands onto panes and its buffer
;; commands onto tabs: C-x 2 splits below, C-x 3 splits right, C-x 0 closes,
;; C-x 1 zooms, C-x o moves to the next pane, C-x b picks a pane by name, and
;; C-x <left> / C-x <right> walk the tabs the way they walk buffers in Emacs.
;;
;; This module is the macOS twin of `(heks-linux wezterm)'.  The two repos share
;; no library, so the renderers and `wezterm-lua-runtime' are duplicated
;; verbatim, the way the `lesskey' file and the shell libs already are: the
;; colours, the shell and the font differ, everything else is the same.

(define-module (cask-and-cons wezterm)
  #:declarative? #t
  #:use-module (srfi srfi-1)
  #:use-module (cask-and-cons prelude)
  #:use-module (cask-and-cons user-settings)
  #:export (wezterm-palette wezterm-yield-apps
                            wezterm-font-family
                            wezterm-font-fallbacks
                            wezterm-font-size
                            wezterm-window-opacity
                            wezterm-window-padding
                            wezterm-window-blur
                            wezterm-scrollback-lines
                            wezterm-prefix-timeout
                            wezterm-default-prog
                            wezterm-config-dir
                            wezterm-config-filename
                            wezterm-raw-lua
                            wezterm-raw-lua?
                            wezterm-compact
                            wezterm-compact?
                            translate-wezterm-mods
                            serialize-wezterm-name
                            serialize-wezterm-value
                            serialize-wezterm-key
                            serialize-wezterm-prefix-entry
                            wezterm-font
                            wezterm-colors
                            wezterm-window-padding-table
                            wezterm-settings
                            wezterm-emacs-keys
                            wezterm-prefix-tables
                            wezterm-yield-app-lines
                            wezterm-emacs-key-lines
                            wezterm-prefix-table-lines
                            wezterm-config
                            serialize-wezterm-config
                            wezterm-lua-runtime
                            install-wezterm-config))

;; --- Settings ---

;; The palette, as semantic keys.  It is the `ayu-dark' the Emacs bridge asks
;; Heks Emacs to load (see `emacs-bridge-forms'), with the face colours Heks
;; Emacs overrides on top of the upstream theme: the default foreground, the
;; cursor and the hl-line background.  There is no palette registry on macOS, so
;; the values live here.
(define wezterm-palette
  (make-parameter '(("foreground" . "#d4d1cc") ("background" . "#0f1419")
                    ("cursor_bg" . "#ffb07c")
                    ("cursor_fg" . "#0f1419")
                    ("selection_fg" . "#d4d1cc")
                    ("selection_bg" . "#1d252a"))))

;; The applications that get the keyboard back while they run.  The list is
;; matched against the base name of the pane's foreground process, lower-cased,
;; so a full path such as /opt/homebrew/bin/less matches `less'.  It covers the
;; cases the rest of the project cares about - Emacs and the pager first of all -
;; plus the editors, the multiplexers and the REPLs, which take their keys from
;; the same Emacs vocabulary (readline, for one, has its own C-x prefix).
(define wezterm-yield-apps
  (make-parameter '("alsamixer" "atop"
                    "bat"
                    "btop"
                    "byobu"
                    "cava"
                    "cmus"
                    "emacs"
                    "emacsclient"
                    "fzf"
                    "ghci"
                    "gitui"
                    "guile"
                    "helix"
                    "htop"
                    "hx"
                    "info"
                    "ipython"
                    "irb"
                    "irssi"
                    "joe"
                    "jshell"
                    "kak"
                    "lazygit"
                    "less"
                    "lf"
                    "lua"
                    "man"
                    "mc"
                    "mcedit"
                    "micro"
                    "mongosh"
                    "more"
                    "most"
                    "mosh"
                    "mutt"
                    "nano"
                    "ncspot"
                    "neomutt"
                    "newsboat"
                    "nnn"
                    "nvim"
                    "nvtop"
                    "pg"
                    "pico"
                    "psql"
                    "python"
                    "python3"
                    "ranger"
                    "redis-cli"
                    "rmpc"
                    "sbcl"
                    "screen"
                    "sqlite3"
                    "ssh"
                    "telnet"
                    "tig"
                    "tmux"
                    "top"
                    "tuir"
                    "vi"
                    "view"
                    "vim"
                    "weechat"
                    "yazi")))

;; The monospaced family, the same one the Emacs bridge gives Heks Emacs.
(define wezterm-font-family
  (make-parameter "Intel One Mono"))

;; Fallback families, for the glyphs the monospaced font does not carry.
(define wezterm-font-fallbacks
  (make-parameter '("Apple Color Emoji")))

;; Terminal font size, in points.
(define wezterm-font-size
  (make-parameter 12))

;; Background opacity.
(define wezterm-window-opacity
  (make-parameter 0.88))

;; How much macOS blurs what is behind the window, in points.  iTerm2 was
;; configured by hand for this; WezTerm can declare it.
(define wezterm-window-blur
  (make-parameter 20))

;; Window padding, in pixels, applied on every side.
(define wezterm-window-padding
  (make-parameter 16))

;; Number of scrollback lines kept per pane, as the README asks of the other
;; terminal.
(define wezterm-scrollback-lines
  (make-parameter 100000))

;; How long a prefix table waits for its second key, in milliseconds.  Emacs has
;; no such timeout, but a key table that never resolves would swallow every key,
;; so an abandoned C-x gives up on its own.
(define wezterm-prefix-timeout
  (make-parameter 4000))

;; The shell to start.  The ZSH configuration installed by `install-zsh-config'
;; is a login shell, so WezTerm has to start one too.
(define wezterm-default-prog
  (make-parameter '("/bin/zsh" "-l")))

;; WezTerm's configuration directory; defaults to ~/.config/wezterm.
(define wezterm-config-dir
  (make-parameter (format #f "~a/.config/wezterm"
                          (or (getenv "HOME") "/tmp"))))

;; WezTerm reads wezterm.lua from its configuration directory.
(define wezterm-config-filename
  (make-parameter "wezterm.lua"))

;; --- Lua values ---

(define (wezterm-raw-lua text)
  "Return @var{text} wrapped so that `serialize-wezterm-value' emits it as
literal Lua instead of quoting it.

@example
(serialize-wezterm-value (wezterm-raw-lua \"act.TogglePaneZoomState\"))
@result{} act.TogglePaneZoomState
@end example"
  (cons 'raw-lua text))

(define (wezterm-raw-lua? value)
  "Return @code{#t} when @var{value} is a literal Lua fragment."
  (and (pair? value)
       (eq? (car value)
            'raw-lua)
       (string? (cdr value))))

(define (wezterm-compact value)
  "Return @var{value} marked to be rendered as a single-line Lua table, for
values short enough that spreading them over several lines would only add noise."
  (cons 'compact-lua value))

(define (wezterm-compact? value)
  "Return @code{#t} when @var{value} was marked with `wezterm-compact'."
  (and (pair? value)
       (eq? (car value)
            'compact-lua)))

(define (wezterm-wrapped? value)
  "Return @code{#t} when @var{value} is a tagged Lua fragment rather than data."
  (or (wezterm-raw-lua? value)
      (wezterm-compact? value)))

(define (wezterm-indent level)
  "Return the indentation string for @var{level} nested Lua tables."
  (make-string (* 2 level) #\space))

;; Width of the section banners of the generated file.
(define wezterm-banner-width
  74)

(define* (wezterm-banner #:key title)
  "Render a section banner for the generated file.

Keeping the width here rather than inside each heading is what makes the
sections line up."
  (string-append "-- ===== " title " "
                 (make-string (max 3
                                   (- wezterm-banner-width 10
                                      (string-length title))) #\=)))

(define (wezterm-name? name)
  "Return @code{#t} when @var{name} can key a Lua table field."
  (or (string? name)
      (symbol? name)))

(define (serialize-wezterm-name name)
  "Render @var{name} as a Lua table field name.

Names that are not a valid Lua identifier - @code{emacs-cx}, for instance - are
bracketed and quoted, the way Lua requires.

@example
(serialize-wezterm-name \"emacs-cx\")
@result{} ['emacs-cx']
@end example"
  (let* ((name (if (symbol? name)
                   (symbol->string name) name))
         (identifier? (string-every (lambda (c)
                                      (or (char-alphabetic? c)
                                          (char-numeric? c)
                                          (char=? c #\_))) name)))
    (if identifier? name
        (format #f "['~a']" name))))

(define (wezterm-object? value)
  "Return @code{#t} when @var{value} is a Lua table keyed by field names.

A list of pairs whose keys are strings or symbols is an object, which is what
the palette, the settings tables and the key bindings all are.  A list of
anything else is an array, and a tagged fragment is never an object."
  (and (pair? value)
       (not (wezterm-wrapped? value))
       (every (lambda (entry)
                (and (pair? entry)
                     (not (wezterm-wrapped? entry))
                     (wezterm-name? (car entry)))) value)))

(define* (serialize-wezterm-table lines
                                  #:key (level 0) compact?)
  "Join rendered Lua @var{lines} into one table expression.

@var{level} is the nesting depth, used for indentation, and @var{compact?} keeps
the whole table on the line it starts on."
  (cond
    ((null? lines)
     "{}")
    (compact? (format #f "{ ~a }"
                      (string-join lines ", ")))
    (else (string-append "{"
                         "\n"
                         (string-join (map (lambda (line)
                                             (string-append (wezterm-indent (1+
                                                                             level))
                                                            line ",")) lines)
                                      "\n")
                         "\n"
                         (wezterm-indent level)
                         "}"))))

(define* (serialize-wezterm-value value
                                  #:key (level 0) compact?)
  "Render @var{value} as a Lua expression.

Strings are single-quoted - Lua's spelling, and it keeps the generated file free
of escapes - numbers and booleans pass through, a list of pairs becomes a Lua
object and any other list becomes a Lua array.  Tables are laid out one entry per
line unless the value was wrapped in `wezterm-compact', and literal Lua fragments
from `wezterm-raw-lua' are emitted verbatim.

@example
(serialize-wezterm-value #t)
@result{} true
@end example"
  (cond
    ((wezterm-raw-lua? value)
     (cdr value))
    ((wezterm-compact? value)
     (serialize-wezterm-value (cdr value)
                              #:level level
                              #:compact? #t))
    ((eq? value #t)
     "true")
    ((eq? value #f)
     "false")
    ((string? value)
     (format #f "'~a'" value))
    ((number? value)
     (format #f "~a" value))
    ((null? value)
     "{}")
    ((wezterm-object? value)
     (serialize-wezterm-table (map (lambda (entry)
                                     (format #f "~a = ~a"
                                             (serialize-wezterm-name (car
                                                                      entry))
                                             (serialize-wezterm-value (cdr
                                                                       entry)
                                              #:level (1+ level)
                                              #:compact? compact?))) value)
                              #:level level
                              #:compact? compact?))
    ((list? value)
     (serialize-wezterm-table (map (lambda (item)
                                     (serialize-wezterm-value item
                                                              #:level (1+
                                                                       level)
                                                              #:compact?
                                                              compact?)) value)
                              #:level level
                              #:compact? compact?))
    (else (error "serialize-wezterm-value: cannot render as Lua:" value))))

(define (translate-wezterm-mods mods)
  "Translate the project's short modifier syntax into WezTerm's spelling.

WezTerm separates modifiers with a vertical bar and spells them out in capitals.
Unknown parts are passed through unchanged, so a literal key name survives.

For example, @code{C-S} becomes @code{CTRL|SHIFT}."
  (let* ((parts (string-split mods #\-))
         (translated-parts (map (lambda (p)
                                  (cond
                                    ((string=? p "C")
                                     "CTRL")
                                    ((string=? p "M")
                                     "ALT")
                                    ((string=? p "S")
                                     "SHIFT")
                                    ((string=? p "s")
                                     "SUPER")
                                    (else p))) parts)))
    (string-join translated-parts "|")))

(define* (serialize-wezterm-key #:key key mods action)
  "Render one guarded key assignment as an inline Lua table.

@var{mods} uses the short syntax translated by `translate-wezterm-mods', @var{key}
is a WezTerm key name and @var{action} is the Lua expression the chord performs
when no application owns the keyboard.

@example
(serialize-wezterm-key #:key \"y\" #:mods \"C\" #:action \"act.PasteFrom 'Clipboard'\")
@result{} { key = 'y', mods = 'CTRL', action = act.PasteFrom 'Clipboard' }
@end example"
  (format #f "{ key = '~a', mods = '~a', action = ~a }" key
          (translate-wezterm-mods mods) action))

(define* (serialize-wezterm-prefix-entry #:key key action)
  "Render one entry of a prefix key table as an inline Lua table.

Unlike `serialize-wezterm-key', an entry carries no modifier of its own: the
runtime expands it into the two spellings a prefix needs - with and without
@code{CTRL} still held down - so that both @kbd{C-x 2} and @kbd{C-x} then
@kbd{2} work."
  (format #f "{ key = '~a', action = ~a }" key action))

;; --- The configuration ---

(define* (wezterm-font)
  "Return the Lua expression for the @code{font} setting.

The family comes from `wezterm-font-family', which is the family the Emacs bridge
gives Heks Emacs, so terminal and editor agree; `wezterm-font-fallbacks' supplies
the families WezTerm falls back to for glyphs the main font lacks."
  (wezterm-raw-lua (format #f "wezterm.font_with_fallback { ~a }"
                           (string-join (map (lambda (family)
                                               (format #f "'~a'" family))
                                             (cons (wezterm-font-family)
                                                   (wezterm-font-fallbacks)))
                                        ", "))))

(define* (wezterm-colors)
  "Return the Lua @code{colors} table, taken from `wezterm-palette'.

The cursor and the selection borrow the palette's highlight colours, so the
terminal looks like the Emacs frame next to it."
  (wezterm-palette))

(define* (wezterm-window-padding-table)
  "Return the @code{window_padding} table, one entry per side.

WezTerm wants the four sides spelled out; `wezterm-window-padding' holds the
single number they all take."
  (wezterm-compact (list (cons 'left
                               (wezterm-window-padding))
                         (cons 'right
                               (wezterm-window-padding))
                         (cons 'top
                               (wezterm-window-padding))
                         (cons 'bottom
                               (wezterm-window-padding)))))

(define* (wezterm-settings)
  "Return the settings WezTerm receives, as an association list.

The renderer turns this into the @code{settings} table of the generated file,
which is then copied onto the configuration one field at a time.  Every value
here is either a parameter or derived from the palette and the font settings, so
changing a setting is enough to change the file.

@example
(assoc-ref (wezterm-settings) \"scrollback_lines\")
@result{} 100000
@end example"
  `(("font" unquote
     (wezterm-font))
    ("font_size" unquote
     (wezterm-font-size))
    ("window_padding" unquote
     (wezterm-window-padding-table))
    ("window_background_opacity" unquote
     (wezterm-window-opacity))
    ("macos_window_background_blur" unquote
     (wezterm-window-blur))
    ("scrollback_lines" unquote
     (wezterm-scrollback-lines))
    ("default_prog" unquote
     (wezterm-compact (wezterm-default-prog)))
    ("hide_tab_bar_if_only_one_tab" . #t)
    ("adjust_window_size_when_changing_font_size" . #f)
    ("colors" unquote
     (wezterm-colors))))

(define* (wezterm-emacs-keys)
  "Return the rendered guarded key assignments, one inline Lua table each.

Every chord here is one an Emacs user reaches for, so every one of them is
guarded: the runtime hands it back to the application whenever
`wezterm-yield-apps' owns the keyboard.  The set is deliberately small, and two
chords are missing on purpose:

- C-v and M-v are not bound at all.  They belong to the pager (forw-screen and
  back-screen in the shared lesskey file) and to Emacs's own scrolling, so the
  scrollback pages with S-PageUp and S-PageDown.
- C-c is not bound either.  It is Emacs's leader key, but in a terminal it is
  also the interrupt signal, and no terminal may take it.

Creating and renaming tabs is left to WezTerm's own defaults in the Cmd/Ctrl+Shift
namespace, which neither Emacs nor a pager wants."
  (list (serialize-wezterm-key #:key "x"
                               #:mods "C"
                               #:action (format #f
                                         "act.ActivateKeyTable { name = 'emacs-cx', one_shot = true, until_unknown = true, timeout_milliseconds = ~a }"
                                         (wezterm-prefix-timeout)))
        (serialize-wezterm-key #:key "y"
                               #:mods "C"
                               #:action "act.PasteFrom 'Clipboard'")
        (serialize-wezterm-key #:key "w"
                               #:mods "M"
                               #:action
                               "act.CopyTo 'ClipboardAndPrimarySelection'")
        (serialize-wezterm-key #:key "="
                               #:mods "C"
                               #:action "act.IncreaseFontSize")
        (serialize-wezterm-key #:key "-"
                               #:mods "C"
                               #:action "act.DecreaseFontSize")
        (serialize-wezterm-key #:key "0"
                               #:mods "C"
                               #:action "act.ResetFontSize")
        (serialize-wezterm-key #:key "s"
                               #:mods "M"
                               #:action
                               "act.Search { CaseInSensitiveString = '' }")
        (serialize-wezterm-key #:key "LeftArrow"
                               #:mods "S"
                               #:action "act.ActivatePaneDirection 'Left'")
        (serialize-wezterm-key #:key "RightArrow"
                               #:mods "S"
                               #:action "act.ActivatePaneDirection 'Right'")
        (serialize-wezterm-key #:key "UpArrow"
                               #:mods "S"
                               #:action "act.ActivatePaneDirection 'Up'")
        (serialize-wezterm-key #:key "DownArrow"
                               #:mods "S"
                               #:action "act.ActivatePaneDirection 'Down'")
        (serialize-wezterm-key #:key "PageUp"
                               #:mods "S"
                               #:action "act.ScrollByPage(-1)")
        (serialize-wezterm-key #:key "PageDown"
                               #:mods "S"
                               #:action "act.ScrollByPage(1)")
        (serialize-wezterm-key #:key "Home"
                               #:mods "S"
                               #:action "act.ScrollToTop")
        (serialize-wezterm-key #:key "End"
                               #:mods "S"
                               #:action "act.ScrollToBottom")))

(define* (wezterm-prefix-tables)
  "Return the prefix key tables, as a list of @code{(name . entries)} pairs.

@code{emacs-cx} is Emacs's C-x prefix, mapped onto panes and tabs: the window
commands keep their Emacs keys (2 splits below, 3 splits right, 0 closes, 1
zooms, o is the next pane), b picks a pane the way C-x b picks a buffer, and the
arrow keys walk the tabs the way they walk buffers.  g quits, as C-g does in
Emacs.

The table is only reachable through a guarded C-x, so Emacs and the pager never
lose their prefix."
  `(("emacs-cx" ("2" . "act.SplitVertical { domain = 'CurrentPaneDomain' }")
     ("3" . "act.SplitHorizontal { domain = 'CurrentPaneDomain' }")
     ("0" . "act.CloseCurrentPane { confirm = true }")
     ("1" . "act.TogglePaneZoomState")
     ("o" . "act.ActivatePaneDirection 'Next'")
     ("b" . "act.PaneSelect")
     ("LeftArrow" . "act.ActivateTabRelative(-1)")
     ("RightArrow" . "act.ActivateTabRelative(1)")
     ("g" . "act.PopKeyTable"))))

(define (wezterm-yield-app-lines)
  "Return the rendered lines of the @code{yield_apps} set."
  (map (lambda (app)
         (format #f "  ['~a'] = true," app))
       (wezterm-yield-apps)))

(define (wezterm-emacs-key-lines)
  "Return the rendered lines of the @code{emacs_keys} array."
  (map (lambda (key)
         (format #f "  ~a," key))
       (wezterm-emacs-keys)))

(define (wezterm-prefix-table-lines)
  "Return the rendered lines of the @code{emacs_prefix_tables} table."
  (append-map (lambda (table)
                (append (list (format #f "  ~a = {"
                                      (serialize-wezterm-name (car table))))
                        (map (lambda (entry)
                               (format #f "    ~a,"
                                       (serialize-wezterm-prefix-entry #:key (car
                                                                              entry)
                                                                       #:action
                                                                       (cdr
                                                                        entry))))
                             (cdr table))
                        (list "  },")))
              (wezterm-prefix-tables)))

;; The mechanism, as opposed to the policy.  It is plain Lua and is emitted as
;; written: it reads `yield_apps', `settings', `emacs_keys' and
;; `emacs_prefix_tables' from the generated part above and turns them into a
;; WezTerm configuration.  The only Lua syntax constraint the renderer imposes is
;; that this block is written with single-quoted strings and no backslashes, so
;; that it needs no escaping inside the Scheme string it lives in.
(define wezterm-lua-runtime
  "-- Strip the directory part of a path, so that '/usr/bin/less' and 'less'
-- compare equal.
local function basename(path)
  return (path:gsub('^.*/', ''))
end

-- True when the process in front of this pane is one of the applications that
-- must receive the keys itself.  When the name cannot be determined the
-- terminal keeps its own bindings rather than swallowing a chord.
local function application_owns_keyboard(pane)
  if not pane then
    return false
  end
  local ok, name = pcall(function()
    return pane:get_foreground_process_name()
  end)
  if not ok or type(name) ~= 'string' or name == '' then
    return false
  end
  return yield_apps[basename(name):lower()] == true
end

-- Re-send a chord to the pane, encoded the way the application expects it.
local function send_key(spec)
  local assignment = { key = spec.key }
  if spec.mods and spec.mods ~= 'NONE' then
    assignment.mods = spec.mods
  end
  return act.SendKey(assignment)
end

-- Wrap one key assignment so that the application wins when it owns the
-- keyboard.
local function guarded(spec)
  return {
    key = spec.key,
    mods = spec.mods,
    action = wezterm.action_callback(function(window, pane)
      if application_owns_keyboard(pane) then
        window:perform_action(send_key(spec), pane)
      else
        window:perform_action(spec.action, pane)
      end
    end),
  }
end

-- A prefix table has to match the chord whether the modifier is still held
-- down (C-x 2, as in Emacs) or released in between (C-x, then 2).
local function prefix_table(entries)
  local assignments = {}
  for _, entry in ipairs(entries) do
    for _, mods in ipairs { 'NONE', 'CTRL' } do
      assignments[#assignments + 1] = {
        key = entry.key,
        mods = mods,
        action = entry.action,
      }
    end
  end
  return assignments
end

-- ===== wiring ==========================================================

for name, value in pairs(settings) do
  config[name] = value
end

-- Build the lists aside and assign them whole: reading an unset field of the
-- config builder yields a fresh default table each time, so inserting straight
-- into config.keys would be lost.
local keys = {}
for _, spec in ipairs(emacs_keys) do
  keys[#keys + 1] = guarded(spec)
end
config.keys = keys

local key_tables = {}
for name, entries in pairs(emacs_prefix_tables) do
  key_tables[name] = prefix_table(entries)
end
config.key_tables = key_tables")

(define* (wezterm-config)
  "Return the complete WezTerm configuration as a list of text lines.

The file is assembled in four parts, in the order WezTerm needs them: the
generated application set, the generated settings, the generated key bindings,
and finally `wezterm-lua-runtime', which consumes all three.  Passing the result
to @code{string-join} with a newline produces the file that is written to disk;
`serialize-wezterm-config' does exactly that."
  (append (list "-- ====== Cask and Cons WezTerm configuration ======"
           "--"
           "-- auto-generated file, DO NOT EDIT!"
           "-- Generated by (cask-and-cons wezterm); install it with"
           "-- `./caco install-wezterm'.  Edit src/cask-and-cons/wezterm.scm instead."
           "--"
           "-- The key bindings are the Emacs ones, and every chord WezTerm"
           "-- claims is guarded: while Emacs, a pager or another full-screen"
           "-- program owns the keyboard the chord is handed back to it."
           "")
          (list "local wezterm = require 'wezterm'"
                "local act = wezterm.action"
                "local config = wezterm.config_builder()" "")
          (list (wezterm-banner #:title
                 "generated: applications that own the keyboard") ""
                "local yield_apps = {")
          (wezterm-yield-app-lines)
          (list "}" "")
          (list (wezterm-banner #:title "generated: settings") ""
                (format #f "local settings = ~a"
                        (serialize-wezterm-value (wezterm-settings))) "")
          (list (wezterm-banner #:title "generated: key bindings") ""
                "local emacs_keys = {")
          (wezterm-emacs-key-lines)
          (list "}" "" "local emacs_prefix_tables = {")
          (wezterm-prefix-table-lines)
          (list "}" ""
                (wezterm-banner #:title
                 "static runtime: keep the keyboard out of the way") "")
          (list wezterm-lua-runtime)
          (list "" "return config" "")))

(define* (serialize-wezterm-config #:key config)
  "Join a configuration line list, such as `(wezterm-config)', into one string
with newlines between the lines.

@example
(serialize-wezterm-config #:config (wezterm-config))
@end example"
  (string-join config "\n"))

(define (install-wezterm-config)
  "Write the WezTerm configuration to `wezterm-config-dir'.

Local overrides are read from
@file{$XDG_CONFIG_HOME/cask-and-cons/wezterm-settings.scm} first, so this machine
can change the font, the opacity or the list of applications that get the
keyboard without editing this module.  WezTerm reloads its configuration when the
file changes, so no restart is needed."
  (log-info "Installing WezTerm configuration")
  (load-local-overrides '(cask-and-cons wezterm)
                        'wezterm-settings)
  (let ((dir (wezterm-config-dir)))
    (unless (file-exists? dir)
      (system* "mkdir" "-p" dir))
    (install-config-file! #:name (wezterm-config-filename)
                          #:dir dir
                          #:contents (serialize-wezterm-config #:config (wezterm-config))))
  (log-success "Installed WezTerm configuration"))
