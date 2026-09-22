;;; -*- lexical-binding: t; -*-
(setq gc-cons-threshold 100000000)     ;; Delay the garabage collection

(setq read-process-output-max (* 1024 1024)) ;; 1mb

;; Save the original handlers once.  `defvar' so that re-loading this
;; file (M-x reload-config, eval-buffer on init.el) can't overwrite the
;; saved copy with an already-emptied list.
(defvar file-name-handler-alist-original file-name-handler-alist
  "Value of `file-name-handler-alist' before startup disabled it.")

(defun restore-file-name-handler-alist ()
  "Put back the handlers disabled for startup speed.
Appends rather than overwrites, so handlers registered while the list
was empty (epa, tramp-archive) are kept."
  (setq gc-cons-threshold 800000)
  (setq file-name-handler-alist
        (delete-dups (append file-name-handler-alist
                             file-name-handler-alist-original))))

(if after-init-time
    ;; Re-loading the config in a running Emacs: there is no startup left
    ;; to speed up, and `emacs-startup-hook' will never run again, so
    ;; emptying the list here would permanently break TRAMP.
    (restore-file-name-handler-alist)
  (setq file-name-handler-alist nil)
  (add-hook 'emacs-startup-hook #'restore-file-name-handler-alist))
