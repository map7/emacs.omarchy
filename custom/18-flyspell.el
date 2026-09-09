(require 'flyspell)
(setq flyspell-issue-message-flg nil)
;; "british" is an aspell dictionary name. Only hunspell is installed here, and
;; it wants locale-style names, so "british" resolved to nothing and every
;; org buffer threw "Error enabling Flyspell mode: Can't find Hunspell
;; dictionary with a .aff affix file". en_AU comes from the hunspell-en_au package.
(setq ispell-dictionary "en_AU")

(add-hook 'enh-ruby-mode-hook
          (lambda () (flyspell-prog-mode)))

(add-hook 'web-mode-hook
          (lambda () (flyspell-prog-mode)))

(add-hook 'coffee-mode-hook
	  (lambda () (flyspell-prog-mode)))

(add-hook 'org-mode-hook
	  (lambda () (flyspell-prog-mode)))


(add-hook 'haml-mode-hook
	  (lambda () ('flymake-haml-load)))


;; flyspell mode breaks auto-complete mode without this.
;;(ac-flyspell-workaround)
