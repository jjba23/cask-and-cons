;;; cask-and-cons

;;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; SPDX-License-Identifier: MIT

;;; Commentary:
;;
;; The environment `maak docs' runs in.
;;
;; The install tasks need nothing from Guix: they are Scheme in src/ driving the
;; programs a macOS machine already has (brew, defaults, launchctl, ...).  This
;; manifest exists for the other half - the API reference - and is entered
;; through `guix time-machine --channels=channels.scm', because `guile-dokgen'
;; lives in the jointhefreeworld channel rather than in Guix itself.
;;
;;   guix time-machine --channels=channels.scm -- shell -m manifest.scm \
;;        -- dokgen api --destination doc/api ./src/cask-and-cons
;;
;; which is exactly what the task does, so the command can be run by hand too.
;;
;;; Code:

(use-modules (guix packages)
             (gnu packages)
             (gnu packages guile)
             (gnu packages guile-xyz)
             (gnu packages texinfo))

(packages->manifest
 (list
  ;; The modules are Guile 3.0 and use nothing beyond it: (ice-9 ...) and
  ;; (srfi ...), plus the files next to them in src/cask-and-cons/.
  guile-3.0
  ;; `texi2any' renders the Texinfo dokgen writes into the HTML page; dokgen
  ;; writes the Texinfo, not the page.
  (specification->package "texinfo")
  ;; guile-config and guile-lib are propagated by guile-dokgen already; naming
  ;; guile-lib is harmless and keeps the environment honest about what the
  ;; modules are read with.
  guile-lib
  ;; The reference itself.  A `specification->package' rather than a variable:
  ;; it is the name the channel publishes, and the pin in channels.scm is what
  ;; decides which revision of it is meant.
  (specification->package "guile-dokgen")))
