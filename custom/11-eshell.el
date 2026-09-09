;; Disable yasnippets in shell so we can regain our tab autocomplete  -*- lexical-binding: t; -*-
(add-hook 'term-mode-hook (lambda()
                (yas-minor-mode -1)))
