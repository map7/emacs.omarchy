;; Load rails snippets
(use-package yasnippet
  :init
  (add-hook 'rails-minor-mode-hook '(lambda () (yas-minor-mode)))
  :defer 5
  :config
  (yas-global-mode 1)
  ;; Was hardcoded to "~/.emacs.default/snippets", so any profile other than
  ;; default read another profile's snippets. Follow the running profile instead.
  (setq yas-snippet-dirs (list (expand-file-name "snippets" user-emacs-directory)))
  )
