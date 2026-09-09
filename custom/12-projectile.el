;;; -*- lexical-binding: t; -*-
(use-package grizzl :defer)
(use-package projectile-rails
  :defer 2
  :init
  (add-hook 'text-mode-hook 'projectile-mode)
  (add-hook 'prog-mode-hook 'projectile-mode)
  ;; Setup projectile-rails
  ;; This is stuffing around with tramp mode.
  (add-hook 'projectile-mode-hook 'projectile-rails-on)

  :bind (:map projectile-rails-mode-map
         ("s-m" . projectile-rails-find-current-model)
         ("s-v" . projectile-rails-find-current-view)
         ("s-c" . projectile-rails-find-current-controller)
         ("s-t" . projectile-rails-find-current-spec)
)
  :config
  (setq projectile-enable-caching t)
  (setq projectile-completion-system 'ivy)
  ;; Only detect projects via VCS / .projectile markers, not stray build
  ;; files (package.json, Gemfile, ...) that would otherwise make the home
  ;; directory a "project" and hang Emacs while indexing it.
  (setq projectile-project-root-functions
        '(projectile-root-local projectile-root-bottom-up))
  ;; Faster, gitignore-aware indexing via external tools.
  (setq projectile-indexing-method 'alien)
  )

;; FIX hange issue with tramp. Tested this 16/02/2017 and it's fixed.
;; https://github.com/bbatsov/prelude/issues/594
(projectile-mode +1)
