;;; cask-and-cons

;;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; SPDX-License-Identifier: MIT

;;; Commentary:
;;
;; The channels the documentation tasks pin.
;;
;; `maak docs' and `maak diagrams' are the only tasks here that enter a Guix
;; shell (`guix time-machine --channels=channels.scm -- shell -m manifest.scm',
;; see manifest.scm).  Pinning the channels is what makes that shell mean the
;; same thing a month from now, on a machine whose own Guix was pulled from
;; somewhere else.
;;
;; This file is not how cask-and-cons boots.  `./bootstrap' installs maak (and
;; sift, ...) from the Nix profile flake.nix describes, and every install-* task
;; runs from that profile; these two channels are only the toolchain the
;; reference is generated with.
;;
;; Guix is pinned to a commit.  The jointhefreeworld channel carries `guile-dokgen',
;; which `(gnu)' does not have, so manifest.scm cannot even load without it; it
;; comes second so its packages take precedence over the copies Guix carries.
;;
;;; Code:

(list (channel
        (name 'guix)
        (url "https://git.guix.gnu.org/guix.git")
        (branch "master")
        (commit "5cea8de04500ba7904e02ee7b53178fb06856e13")
        (introduction
         (make-channel-introduction "9edb3f66fd807b096b48283debdcddccfea34bad"
          (openpgp-fingerprint
           "BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA"))))
       (channel
        (name 'jointhefreeworld)
        (url "https://github.com/jjba23/guix-jointhefreeworld")
        (branch "trunk")
        ;; The collection this configuration is built against: guile-dokgen,
        ;; which `manifest.scm' names, is defined there and not in (gnu).
        (commit "24db897c6c9064ebf2018582c6dca2229dda0e62")
        (introduction
         (make-channel-introduction
          "b0ac3f05075d7959860fc9e1db5871acddea3986"
          (openpgp-fingerprint
           "83BC 6E1C 8726 B8C2 97F8  D16E 24F4 6738 CE11 4AF6")))))
