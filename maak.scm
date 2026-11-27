;;; cask-and-cons

;;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; SPDX-License-Identifier: MIT

;;; Commentary:
;;
;; This is cask-and-cons's Maak file, and it is the whole command line of the
;; project: `maak <task>' from the repository root (or from anywhere, once
;; `install-zsh' has put the `caco' shell function in place).  `maak' lists
;; the tasks, `maak install-git,install-zsh' chains them.
;;
;; Do not have maak yet?  Run `./bootstrap' (see the README); it installs the
;; Nix profile that carries maak.
;;
;; The exports are the task list.  Each task is one thin procedure over a
;; module in src/cask-and-cons/, which is where the work is done.
;;
;; `docs' and `diagrams' are the exception to "the work is in src/": they are
;; about the modules rather than done by them.  Both shell out to tools the
;; machine's own Guix may not have (dokgen, texi2any, mmdc), so they run in the
;; environment manifest.scm describes, at the revision channels.scm pins.  The
;; install tasks keep using the Nix profile `./bootstrap' puts in place.

;; The modules live in ./src, which maak does not put on the load path by
;; itself.  This has to run before the module below is defined.
(eval-when (expand load eval)
  (add-to-load-path
   (string-append (dirname (or (current-filename) "./maak.scm")) "/src")))

;; `scandir' finds the mermaid sources `maak diagrams' renders, and
;; `string-drop-right' names each image after its source.  (`scandir' comes
;; from (ice-9 ftw); `string-drop-right' and `string-suffix?' are core Guile
;; 3.0 procedures, so (srfi srfi-13) would be an unused import here.)
(define-module (maak)
  #:declarative? #f
  #:use-module ((maak maak) #:hide (log-info log-error))
  #:use-module (ice-9 ftw)
  #:use-module (cask-and-cons prelude)
  #:use-module (cask-and-cons git)
  #:use-module (cask-and-cons gpg)
  #:use-module (cask-and-cons brew)
  #:use-module (cask-and-cons omniwm)
  #:use-module (cask-and-cons emacs)
  #:use-module (cask-and-cons zsh)
  #:use-module (cask-and-cons iterm)
  #:use-module (cask-and-cons fonts)
  #:use-module (cask-and-cons macos)
  #:use-module (cask-and-cons skhd)
  #:use-module (cask-and-cons mcp)
  #:use-module (cask-and-cons kotlin-lsp)
  #:use-module (cask-and-cons nix)
  #:use-module (cask-and-cons confluence)
  #:export (default
            compile-sources
            docs
            diagrams
            install-brew
            install-nix
            install-git
            install-gpg
            install-omniwm
            install-zsh
            install-iterm
            install-macos
            install-skhd
            install-mcp
            install-confluence
            hr)
  ;; Tasks whose module function already has the task's name.
  #:re-export (install-emacs-bridge
               install-fontconfig
               install-jetbrains-fonts
               install-kotlin-lsp
               sync-confluence
               login-confluence))

;; The Confluence module finds the repository through this, and writes it into
;; the launchd agent.  Maak runs from the directory of this file.
(setenv "CACO_DIR" (getcwd))

;; ====== Constants ======

;; The stylesheet the generated API page is read with, shared with the other
;; jointhefreeworld projects' references.
(define api-docs-css-url
  "https://jointhefreeworld.org/static/css/jointhefreeworld.css")

;; The name of the project, and so the directory under ./src that holds it.
(define project-name
  'cask-and-cons)

(define (default)
  "List the available tasks."
  (list-tasks))

(define (find-scm-files dir)
  "Recursively collect all @file{.scm} files under @var{dir}."
  (let ((acc '()))
    (ftw dir
         (lambda (filename statinfo flag)
           (when (and (eq? flag 'regular)
                   (string-suffix? ".scm" filename))
             (set! acc (cons filename acc)))
           #t))
    acc))

(define (compile-sources)
  "Byte-compile every .scm file under src/ with guild, warnings at -W3."
  (log-info "Compiling project sources")
  (for-each (lambda (file)
              (log-info "Compiling ~a" file)
              (unless (zero? (system* "guild" "compile" "-L" "src" "-W3" file))
                (log-error "Failed to compile ~a" file)
                (exit 1)))
            (find-scm-files "src"))
  (log-success "Compiled project sources"))

;; ====== Documentation ======
;;
;; The reference is generated, never written: dokgen loads each module in
;; src/cask-and-cons/ and writes the Texinfo its docstrings amount to, texi2any
;; renders that into one HTML page, and the page is put beside the stylesheet,
;; the script and the diagrams it points at.
;;
;; Both tasks run in the environment manifest.scm describes, at the revision
;; channels.scm pins, so `maak docs' means the same thing on a machine that has
;; never pulled the jointhefreeworld channel - which is where dokgen lives.

(define (docs)
  "Generate cask-and-cons's API reference and render it as HTML.

The page is doc/api-dist/index.html.  dokgen reads the modules rather than
their text, so every exported procedure that has a docstring is in the
reference; beside the Texinfo it writes the stylesheet, the script and a
directory of diagrams for the docstrings that carry one, and Texinfo copies
neither, so they are put beside the page that points at them."
  (log-info "Generating the API reference")
  (delete-file-recursively "doc")
  (time-machine-manifest-shell
   (list "dokgen" "api"
         "--destination" "doc/api"
         (~ "./src/~a" project-name))
   #:verbose? #t)
  (mkdir-p "doc/api-dist")
  (time-machine-manifest-shell
   (list "texi2any" "-v" "--html" "--no-split"
         (~ "--css-ref=~a" api-docs-css-url)
         "-I" "doc/api"
         "-c" (shell-quote
               (string-append
                "EXTRA_HEAD="
                "<link rel=\"stylesheet\" href=\"dokgen.css\">"
                "<script src=\"dokgen.js\" defer></script>"))
         "-o" "doc/api-dist/index.html"
         "./doc/api/index.texi")
   #:verbose? #t)
  (for-each (lambda (asset)
              (when (file-exists? (~ "doc/api/~a" asset))
                (cp (~ "doc/api/~a" asset) "doc/api-dist"
                    #:force? #t #:verbose? #t)))
            '("dokgen.css" "dokgen.js"))
  (when (file-exists? "doc/api/diagrams")
    (cp "doc/api/diagrams" "doc/api-dist" #:force? #t #:verbose? #t))
  (log-success "Wrote doc/api-dist/index.html"))

(define (diagrams)
  "Render every mermaid source under resources/diagrams to the SVG beside it.

A diagram is drawn once and committed, both halves of it: the mermaid source and
the SVG rendered beside it, so reading the README needs no renderer.  Rendering
is a task of its own because the renderer is a JavaScript tool, found on $PATH,
which is where `npm install --global @mermaid-js/mermaid-cli' puts it."
  (log-info "Rendering the diagrams")
  (for-each
   (lambda (name)
     (let* ((source (in-vicinity "resources/diagrams" name))
            (image (string-append (string-drop-right source 4) ".svg")))
       ((@ (maak maak) run)
        (list "mmdc" "-i" source "-o" image
              "--backgroundColor" "transparent")
        #:verbose? #t)))
   (scandir "resources/diagrams"
            (lambda (name)
              (and (not (member name '("." "..")))
                   (string-suffix? ".mmd" name)))))
  (log-success "Rendered the diagrams"))

;; ====== Install targets ======

(define (install-brew)
  "Ensure the Homebrew taps, formulae and casks of brew.scm are installed."
  (install-brew-packages))

(define (install-nix)
  "Install the Nix profile (maak, sift and the rest, see flake.nix)."
  (install-nix-tools))

(define (install-git)
  "Install the Git configuration."
  (install-git-config))

(define (install-gpg)
  "Install the GnuPG configuration."
  (install-gpg-config))

(define (install-omniwm)
  "Install the OmniWM configuration."
  (install-omniwm-config))

(define (install-zsh)
  "Install the ZSH configuration (~/.zshrc and the pager keymap)."
  (install-zsh-config))

(define (install-iterm)
  "Install the iTerm2 profile (colours, font, Meta key, scrollback)."
  (install-iterm-config))

(define (install-macos)
  "Converge the macOS system preferences declared in macos.scm."
  (install-macos-settings))

(define (install-skhd)
  "Install the skhd configuration."
  (install-skhd-config))

(define (install-mcp)
  "Write the MCP server config for Copilot (JetBrains, CLI) and ECA."
  (install-mcp-config))

(define (install-confluence)
  "Install the launchd agent that runs sync-confluence weekly."
  (install-confluence-sync))

;; ====== Everything ======

(define install-tasks
  ;; Order matters: brew provides what the later tasks call.
  (list install-brew install-nix install-git install-gpg install-omniwm
        install-emacs-bridge install-zsh install-iterm install-fontconfig
        install-jetbrains-fonts install-macos install-skhd install-mcp
        ;; install-kotlin-lsp
        ;; install-confluence
        ))

(define (hr)
  "Run every install-* task, in dependency order."
  (for-each (lambda (task) (task)) install-tasks))
