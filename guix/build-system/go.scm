;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2016 Petter <petter@mykolab.ch>
;;; Copyright © 2017 Leo Famulari <leo@famulari.name>
;;; Copyright © 2020 Jakub Kądziołka <kuba@kadziolka.net>
;;; Copyright © 2021 Ludovic Courtès <ludo@gnu.org>
;;;
;;; This file is part of GNU Guix.
;;;
;;; GNU Guix is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; GNU Guix is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with GNU Guix.  If not, see <http://www.gnu.org/licenses/>.

(define-module (guix build-system go)
  #:use-module (guix utils)
  #:use-module (guix gexp)
  #:use-module (guix store)
  #:use-module (guix monads)
  #:use-module (guix search-paths)
  #:use-module (guix build-system)
  #:use-module (guix build-system gnu)
  #:use-module (guix packages)
  #:use-module (ice-9 match)
  #:use-module (ice-9 regex)
  #:export (%go-build-system-modules
            go-build
            go-build-system

            go-version->git-ref))

;; Commentary:
;;
;; Standard build procedure for packages using the Go build system.  It is
;; implemented as an extension of 'gnu-build-system'.
;;
;; Code:

(define %go-version-rx
  (make-regexp (string-append
                "(v?[0-9]\\.[0-9]\\.[0-9])" ;"v" prefix can be omitted in version prefix
                "(-|-pre\\.0\\.|-0\\.)"     ;separator
                "([0-9]{14})-"              ;timestamp
                "([0-9A-Fa-f]{12})")))      ;commit hash

(define (go-version->git-ref version)
  "Parse VERSION, a \"pseudo-version\" as defined at
<https://golang.org/ref/mod#pseudo-versions>, and extract the commit hash from
it, defaulting to full VERSION if a pseudo-version pattern is not recognized."
  ;; A module version like v1.2.3 is introduced by tagging a revision in the
  ;; underlying source repository.  Untagged revisions can be referred to
  ;; using a "pseudo-version" like v0.0.0-yyyymmddhhmmss-abcdefabcdef, where
  ;; the time is the commit time in UTC and the final suffix is the prefix of
  ;; the commit hash (see: https://golang.org/ref/mod#pseudo-versions).
  (let* ((version
          ;; If a source code repository has a v2.0.0 or later tag for a file
          ;; tree with no go.mod, the version is considered to be part of the
          ;; v1 module's available versions and is given an +incompatible
          ;; suffix
          ;; (see:https://golang.org/cmd/go/#hdr-Module_compatibility_and_semantic_versioning).
          (if (string-suffix? "+incompatible" version)
              (string-drop-right version 13)
              version))
         (match (regexp-exec %go-version-rx version)))
    (if match
        (match:substring match 4)
        version)))

(define %go-build-system-modules
  ;; Build-side modules imported and used by default.
  `((guix build go-build-system)
    (guix build union)
    ,@%gnu-build-system-modules))

(define (default-go)
  ;; Lazily resolve the binding to avoid a circular dependency.
  (let ((go (resolve-interface '(gnu packages golang))))
    (module-ref go 'go)))

(define* (lower name
                #:key source inputs native-inputs outputs system target
                (go (default-go))
                #:allow-other-keys
                #:rest arguments)
  "Return a bag for NAME."
  (define private-keywords
    '(#:target #:go #:inputs #:native-inputs))

  (and (not target)                               ;XXX: no cross-compilation
       (bag
         (name name)
         (system system)
         (host-inputs `(,@(if source
                              `(("source" ,source))
                              '())
                        ,@inputs

                        ;; Keep the standard inputs of 'gnu-build-system'.
                        ,@(standard-packages)))
         (build-inputs `(("go" ,go)
                         ,@native-inputs))
         (outputs outputs)
         (build go-build)
         (arguments (strip-keyword-arguments private-keywords arguments)))))

(define* (go-build name inputs
                   #:key
                   source
                   (phases '%standard-phases)
                   (outputs '("out"))
                   (search-paths '())
                   (install-source? #t)
                   (import-path "")
                   (unpack-path "")
                   (build-flags ''())
                   (tests? #t)
                   (allow-go-reference? #f)
                   (system (%current-system))
                   (guile #f)
                   (imported-modules %go-build-system-modules)
                   (modules '((guix build go-build-system)
                              (guix build union)
                              (guix build utils))))
  (define builder
    (with-imported-modules imported-modules
      #~(begin
          (use-modules #$@modules)
          (go-build #:name #$name
                    #:source #+source
                    #:system #$system
                    #:phases #$phases
                    #:outputs #$(outputs->gexp outputs)
                    #:search-paths '#$(sexp->gexp
                                       (map search-path-specification->sexp
                                            search-paths))
                    #:install-source? #$install-source?
                    #:import-path #$import-path
                    #:unpack-path #$unpack-path
                    #:build-flags #$build-flags
                    #:tests? #$tests?
                    #:allow-go-reference? #$allow-go-reference?
                    #:inputs #$(input-tuples->gexp inputs)))))

  (mlet %store-monad ((guile (package->derivation (or guile (default-guile))
                                                  system #:graft? #f)))
    (gexp->derivation name builder
                      #:system system
                      #:guile-for-build guile)))

(define go-build-system
  (build-system
    (name 'go)
    (description
     "Build system for Go programs")
    (lower lower)))
