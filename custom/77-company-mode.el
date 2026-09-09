;; Setup company stats to sort most commonly used ones at the top.  -*- lexical-binding: t; -*-

(defun my/company-statistics-add-lexical-cookie (&rest _)
  "Give the company-statistics cache file a `lexical-binding' cookie.
`company-statistics--save' writes the cache as bare Lisp, so Emacs 31
warns about the missing cookie every time the cache is loaded back."
  (when (and (boundp 'company-statistics-file)
             (file-exists-p company-statistics-file))
    (with-temp-buffer
      (set-buffer-multibyte nil)
      (insert-file-contents-literally company-statistics-file)
      (goto-char (point-min))
      (unless (looking-at-p ";.*lexical-binding:")
        (insert ";;; -*- lexical-binding: t; -*-\n")
        (let ((coding-system-for-write 'binary))
          (write-region nil nil company-statistics-file nil 'silent))))))

(advice-add 'company-statistics--save :after
            #'my/company-statistics-add-lexical-cookie)

(use-package company-statistics
  :init
  (company-statistics-mode)
  (add-to-list 'company-backend 'company-ansible) ;; company ansible
  (add-hook 'enh-ruby-mode-hook (lambda () (company-mode))) ;; Load for ruby
  (add-hook 'after-init-hook 'global-company-mode) ;; Use in all buffers
  :defer 5
  )
