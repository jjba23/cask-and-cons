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

;; Per-user, per-machine settings shared across cask-and-cons modules.
;; Individual modules can read/override these via `load-local-overrides'
;; (see `cask-and-cons prelude').

(define-module (cask-and-cons user-settings)
  #:export (notes-directory))

;; Where the notes live.  One place for every consumer: the Emacs bridge sets
;; heks/notes-dir to it and the ZSH config exports it as $NOTES_DIR for the
;; `n' command.  $HOME is understood by both (the Emacs side turns it into ~).
(define notes-directory "$HOME/Hacking/private-notes")
