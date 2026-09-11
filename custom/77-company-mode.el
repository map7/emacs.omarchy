;; Setup company stats to sort most commonly used ones at the top.  -*- lexical-binding: t; -*-

;; `company-statistics--save' writes its cache as a bare `setq' form with no
;; `lexical-binding' cookie, and `company-statistics--load' reads it back with
;; `load', which warns about the missing cookie on every startup (Emacs 30+).
;; The file is pure data, so a cookie is safe.  Patch the file before the mode
;; loads it, and re-add the cookie after each save so it stays fixed.
(defun map7/company-statistics-add-lexbind-cookie (&rest _)
  "Prepend a `lexical-binding' cookie to the company-statistics cache file."
  (let ((file (if (boundp 'company-statistics-file)
                  company-statistics-file
                (expand-file-name "company-statistics-cache.el"
                                  user-emacs-directory))))
    (when (file-exists-p file)
      (with-temp-buffer
        (let ((coding-system-for-read 'binary))
          (insert-file-contents-literally file))
        (goto-char (point-min))
        (unless (looking-at-p ";;; -\\*- lexical-binding")
          (insert ";;; -*- lexical-binding: t; -*-\n")
          (let ((coding-system-for-write 'binary))
            (write-region nil nil file nil 'silent)))))))

;; Run before `company-statistics-mode' below pulls the cache in.
(map7/company-statistics-add-lexbind-cookie)

(use-package company-statistics
  :init
  (company-statistics-mode)
  (add-to-list 'company-backend 'company-ansible) ;; company ansible
  (add-hook 'enh-ruby-mode-hook (lambda () (company-mode))) ;; Load for ruby
  (add-hook 'after-init-hook 'global-company-mode) ;; Use in all buffers
  :config
  (advice-add 'company-statistics--save :after
              #'map7/company-statistics-add-lexbind-cookie)
  :defer 5
  )
