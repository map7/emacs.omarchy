;;; -*- lexical-binding: t; -*-
(use-package scss-mode
  :defer 5
  :init
  ;; scss-mode (20180123, its last release) pushes onto two legacy flymake
  ;; variables at load time. Both went away with the flymake rewrite in Emacs
  ;; 26, so loading the package signals void-variable and the :defer timer
  ;; reports "Error running timer require". Define them so the package loads;
  ;; nothing reads them any more, and scss linting here goes through flycheck.
  (unless (boundp 'flymake-allowed-file-name-masks)
    (defvar flymake-allowed-file-name-masks nil))
  (unless (boundp 'flymake-err-line-patterns)
    (defvar flymake-err-line-patterns nil))
  :config
  ;; disable compile on save
  (setq scss-compile-at-save nil))
