;; Daily count of TODO items, logged to an org table  -*- lexical-binding: t; -*-
;;
;; Once a day, count the TODO headlines in the org files of
;; `count-todo-directories' and add a "| date | count |" row to
;; `count-todo-results-file'.  It runs at 23:59, and again when Emacs
;; exits so a day Emacs is closed early still gets a row.  A date that
;; already has a row is never added twice, so it is safe to run by hand
;; with M-x count-todo-items as often as you like.

(defvar count-todo-directories '("~/org/" "~/org/business/michael/")
  "Directories whose org files (not subdirectories) are counted.")

(defvar count-todo-results-file "~/org/todos-results.org"
  "Org file holding the date/count table.")

(defun count-todo--files ()
  "Return the org files in `count-todo-directories'."
  (mapcan (lambda (dir)
            (directory-files (expand-file-name dir) t "\\`[^.#].*\\.org\\'"))
          count-todo-directories))

(defun count-todo--count-file (file)
  "Return the number of TODO headlines in FILE.
A plain regexp, not org-mode: setting up org in 300 buffers took
seconds, and gave the same total."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((case-fold-search nil))
      (count-matches "^\\*+ TODO\\(?:[ \t]\\|$\\)" (point-min) (point-max)))))

(defun count-todo-total ()
  "Return the number of TODO headlines across `count-todo-directories'."
  (apply #'+ (mapcar #'count-todo--count-file (count-todo--files))))

(defun count-todo-items ()
  "Log today's TODO count to `count-todo-results-file', once per day."
  (interactive)
  (let* ((file (expand-file-name count-todo-results-file))
         (date (format-time-string "%Y-%m-%d"))
         (visiting (find-buffer-visiting file)))
    (if (and visiting (buffer-modified-p visiting))
        (message "count-todo: %s has unsaved changes, skipped" file)
      (with-temp-buffer
        (insert-file-contents file)
        (if (re-search-forward (concat "^| " date " |") nil t)
            (message "count-todo: %s already logged" date)
          (let ((total (count-todo-total)))
            (goto-char (point-max))
            (unless (bolp) (insert "\n"))
            (insert (format "| %s | %5d |\n" date total))
            (write-region nil nil file)
            (when visiting
              (with-current-buffer visiting
                (revert-buffer t t t)))
            (message "count-todo: %s %d TODOs" date total)))))))

;; Every day at 23:59, and on the way out of Emacs.
(defvar count-todo--timer nil)
(when (timerp count-todo--timer)
  (cancel-timer count-todo--timer))
(setq count-todo--timer (run-at-time "23:59" (* 24 60 60) #'count-todo-items))
(add-hook 'kill-emacs-hook #'count-todo-items)
