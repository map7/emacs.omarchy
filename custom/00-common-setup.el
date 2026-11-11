;;; -*- lexical-binding: t; -*-
(load "tab-settings")
(load "backup-settings")
(load "conf-mode-settings")

;;; Disable menu-bar, tool-bar, and scroll-bar.
(if (fboundp 'menu-bar-mode)
    (menu-bar-mode -1))
(if (fboundp 'tool-bar-mode)
    (tool-bar-mode -1))
(if (fboundp 'scroll-bar-mode)
    (scroll-bar-mode -1))

;;; Useful Defaults
(setq inhibit-startup-screen t)           ; Disable startup screen
(setq initial-scratch-message "")         ; Make *scratch* buffer blank
(setq-default frame-title-format '("%b")) ; Make window title the buffer name
(setq ring-bell-function 'ignore)         ; Disable bell sound
(fset 'yes-or-no-p 'y-or-n-p)             ; y-or-n-p makes answering questions faster
(show-paren-mode 1)                       ; Show closing parens by default
(electric-pair-mode 1)                    ; Enable the built in pair mode
(delete-selection-mode 0)                 ; Selected text NOT will be overwritten when you start typing
(global-auto-revert-mode t)               ; Auto-update buffer if file has changed on disk

;; `electric-pair-mode' above moves a closing delimiter onto its own line when
;; RET is pressed between a freshly typed pair, but nothing indents that line,
;; so typing `else {' and hitting RET left the `}' in column 0:
;;
;;     if (a) {
;;         |
;;     }                          <- wanted
;;     }                          <- what actually happened, column 0
;;
;; `electric-indent-mode' only reindents the line point is on, and the closer is
;; a line further down.  Reindent it here instead.  Appended to the hook so it
;; runs after electric-pair has inserted that line.
(defun map7/reindent-closing-delimiter ()
  "Indent a closing delimiter that RET pushed onto its own line."
  ;; Deliberately not conditional on `electric-indent-mode': it is off in some
  ;; code buffers here (js2-mode for one), and that is exactly where the closer
  ;; was being left in column 0.  `electric-indent-inhibit' is still honoured,
  ;; since modes that set it mean it.
  (when (and (eq last-command-event ?\n)
             (not electric-indent-inhibit)
             ;; Only the blank line RET just opened.  electric-pair inserts a
             ;; newline of its own, which runs this hook a second time with
             ;; point on the closer itself - acting then would reindent the line
             ;; below it, which is somebody else's brace.
             (save-excursion
               (beginning-of-line)
               (looking-at-p "[[:blank:]]*$")))
    (save-excursion
      (forward-line 1)
      (when (looking-at-p "[[:blank:]]*[]})]")
        (indent-according-to-mode)))))

(defun map7/enable-reindent-closing-delimiter ()
  "Keep closing delimiters indented in this buffer."
  (add-hook 'post-self-insert-hook #'map7/reindent-closing-delimiter t t))

;; Code buffers only - in prose a line starting with a bracket is just prose.
(add-hook 'prog-mode-hook #'map7/enable-reindent-closing-delimiter)

;; (add-hook 'before-save-hook
;; 	  'delete-trailing-whitespace)          ; Delete trailing whitespace on save

(setq save-abbrevs 'silently)             ;; save abbrevs when files are saved
(global-font-lock-mode t)                 ;; Use highlight colors

(defun reload-config ()
  (interactive)
  (load-file (concat user-emacs-directory "init.el")))


;; --------------------------------------------------------------------------------
;; Colourise the Shell Output
(use-package xterm-color :ensure t)
(require 'xterm-color)

(defun xterm-color-colorize-shell-command-output ()
  "Colorize `shell-command' output."
  (let ((bufs
         (seq-remove
          (lambda (x)
            (not (or (string-prefix-p " *Echo Area" (buffer-name x))
                     (string-prefix-p "*Shell Command" (buffer-name x)))))
          (buffer-list))))
    (dolist (buf bufs)
      (with-current-buffer buf
        (xterm-color-colorize-buffer)))))

(defun xterm-color-colorize-shell-command-output-advice (proc &rest rest)
  (xterm-color-colorize-shell-command-output))

(advice-add 'shell-command :after #'xterm-color-colorize-shell-command-output-advice)
;; --------------------------------------------------------------------------------


;; Completion is handled by company-mode (see 77-company-mode.el)
