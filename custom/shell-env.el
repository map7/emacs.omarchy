;;; shell-env.el --- Load shell env files into the Emacs process -*- lexical-binding: t; -*-

;; Emacs started from a desktop launcher (or the daemon) never sources
;; ~/.zshenv, so exports kept in ~/Sync/.zshenv.apps are invisible to
;; things like invoice_quickbooks.el.  This reads those files directly
;; and pushes each export into `process-environment'.
;;
;;   M-x shell-env-reload   re-read the files after editing them

(require 'cl-lib)
(require 'subr-x)

(defcustom shell-env-files (list (expand-file-name "~/Sync/.zshenv.apps"))
  "Shell files to scan for `export VAR=VALUE' lines.
Missing files are ignored."
  :type '(repeat file)
  :group 'environment)

(defconst shell-env--assignment-re
  "\\`\\(?:export[ \t]+\\)?\\([A-Za-z_][A-Za-z0-9_]*\\)=\\(.*\\)\\'"
  "Matches a shell assignment, with or without a leading `export'.")

(defun shell-env--expand (value seen)
  "Expand $VAR and ${VAR} in VALUE, preferring SEEN over the process env."
  (replace-regexp-in-string
   "\\$\\(?:{\\([A-Za-z_][A-Za-z0-9_]*\\)}\\|\\([A-Za-z_][A-Za-z0-9_]*\\)\\)"
   (lambda (m)
     (let ((name (or (match-string 1 m) (match-string 2 m))))
       (or (cdr (assoc name seen)) (getenv name) "")))
   value t t))

(defun shell-env--parse-file (file)
  "Return an alist of (NAME . VALUE) for the assignments in FILE."
  (let (vars)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (while (not (eobp))
        (let ((line (string-trim (buffer-substring-no-properties
                                  (line-beginning-position)
                                  (line-end-position)))))
          (when (and (not (string-prefix-p "#" line))
                     (string-match shell-env--assignment-re line))
            (let ((name (match-string 1 line))
                  (value (match-string 2 line)))
              ;; Single quotes are literal; everything else interpolates.
              (setq value
                    (cond
                     ((string-match "\\`'\\(.*\\)'\\'" value)
                      (match-string 1 value))
                     ((string-match "\\`\"\\(.*\\)\"\\'" value)
                      (shell-env--expand (match-string 1 value) vars))
                     (t (shell-env--expand value vars))))
              ;; Later assignments win, as in the shell.
              (setq vars (cons (cons name value)
                               (assoc-delete-all name vars))))))
        (forward-line 1)))
    (nreverse vars)))

(defun shell-env-load (&optional quiet)
  "Set every variable exported by `shell-env-files' in this Emacs.
Returns the number of variables set.  Messages unless QUIET."
  (let ((count 0))
    (dolist (file shell-env-files)
      (when (file-readable-p file)
        (condition-case err
            (dolist (pair (shell-env--parse-file file))
              (setenv (car pair) (cdr pair))
              (cl-incf count))
          (error (message "shell-env: failed to read %s: %s"
                          file (error-message-string err))))))
    (unless quiet
      (message "shell-env: loaded %d variable(s)" count))
    count))

(defun shell-env-reload ()
  "Re-read `shell-env-files' into the current Emacs session."
  (interactive)
  (shell-env-load))

(defun shell-env-getenv (name)
  "Return the value of NAME, re-reading `shell-env-files' if it is unset."
  (or (getenv name)
      (progn (shell-env-load t) (getenv name))))

(shell-env-load t)

(provide 'shell-env)
;;; shell-env.el ends here
