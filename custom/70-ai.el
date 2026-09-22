;; September, 2026 - Claude Code in Emacs, via ecc  -*- lexical-binding: t; -*-
;; https://github.com/wakamenod/emacs-claude-code
;;
;; Swapped over from claude-code.el + monet.  That pair ran the CLI's own TUI
;; inside an eat terminal, which is where the scroll-anchoring advice and the
;; single-window PTY workaround came from.  ecc speaks the CLI's stream-json
;; protocol in headless mode and renders the session into ordinary Emacs
;; buffers, so there is no terminal emulator and none of that is needed.
;;
;; M-x ecc-start in a project.  C-c C-c sends, RET is a line break, C-c C-a
;; and C-c C-d allow or deny a tool request from any buffer, C-c ? is the menu.

;; posframe backs the usage and side-query popups.  markdown-mode, for the
;; plan and review buffers, already comes from 23-markdown.el.
(use-package posframe)


;; ~/.zshenv exports ANTHROPIC_API_KEY.  The daemon starts from systemd and
;; never sees it, but an Emacs started from a shell does, and the CLI then
;; runs on that key (`subscriptionType: null') instead of the claude.ai Max
;; account.  Nothing else in this config reads it.  M-x ecc-auth-show-status
;; reports which account a session would use.
(setenv "ANTHROPIC_API_KEY" nil)

(use-package ecc
  :vc (:url "https://github.com/wakamenod/emacs-claude-code" :rev :newest)
  :bind-keymap ("C-c c" . ecc-global-map)
  :init
  ;; What claude-code.el passed as `claude-code-program-switches'.
  ;; `ecc-extra-args' is appended to every CLI invocation.
  (setq ecc-extra-args '("--channels" "plugin:telegram@claude-plugins-official"))
  :custom
  ;; Side-by-side review of everything a session changed.
  (ecc-review-style 'ediff)
  (ecc-notify-level 'pulse)
  (ecc-usage-display 'posframe)
  (ecc-btw-display 'posframe)
  (ecc-prompt-suggestions-enabled t)
  ;; The Emacs MCP server: xref, imenu and flymake.  This is the job monet
  ;; did for claude-code.el.
  (ecc-mcp-enabled t)
  ;; `ecc-permission-mode' left at its default on purpose: ecc asks, and
  ;; answering from any buffer is the point of the swap.  Set it to "auto"
  ;; here if the asking gets old.
  )

;; --------------------------------------------------------------------------------
;; c3po was the first interaction I got with ChatGPT in Emacs
(use-package c3po
  :straight (:host github :repo "d1egoaz/c3po.el"))

(when (file-exists-p "~/.emacs.c3po.el")
    (load "~/.emacs.c3po.el"))  ; Email settings


;; gptel is a LLM chat client for Emacs which handles heaps of models & backends.
(straight-use-package 'gptel)

;; (use-package gptel-watch
;;   :after gptel
;;   :config
;;   (gptel-watch-global-mode 1))  ;; Optional: enable globally

(when (file-exists-p "~/.emacs.gptel.el")
  (load "~/.emacs.gptel.el"))

;; ;; --------------------------------------------------------------------------------
;; ;; gptel
;; ;; Is a LLM chat client for Emacs which handles heaps of models & backends.

;; (use-package gptel
;;   :ensure t
;;   :config
;;   (setq gptel-api-key
;;         (let ((auth-info (car (auth-source-search
;;                                :host "api.openai.com"
;;                                :user "openai"
;;                                :require '(:user :secret)))))
;;           (message "Auth info: %S" auth-info)  ;; Debug print
;;           (when auth-info
;;             (let ((secret (plist-get auth-info :secret)))
;;               (if (functionp secret)
;;                   (funcall secret)
;;                 secret)))))
;;   :bind ("C-c g" . 'gptel)
;;   )

;; ;; Llamafile
;; (setq
;;  gptel-model   'test
;;  gptel-backend (gptel-make-openai "llama-cpp"
;;                  :stream t
;;                  :protocol "http"
;;                  :host "localhost:8080"
;;                  :models '(test)))


;; ;; --------------------------------------------------------------------------------
;; ;; Ellama
;; (use-package ellama
;;   :ensure t
;;   :bind ("C-c e" . ellama)
;;   ;; send last message in chat buffer with C-c C-c
;;   :hook (org-ctrl-c-ctrl-c-final . ellama-chat-send-last-message)
;;   :init (setopt ellama-auto-scroll t)
;;   :config
;;   ;; show ellama context in header line in all buffers
;;   (ellama-context-header-line-global-mode +1)
;;   ;; show ellama session id in header line in all buffers
;;   (ellama-session-header-line-global-mode +1))

;; ;; --------------------------------------------------------------------------------
;; ;; aider [18/07/2025]
;; ;; --------------------------------------------------------------------------------
;; (use-package aider
;;   :after transient
;;   :config
;;   ;; ;; For latest claude sonnet model
;;   ;; (setq aider-args '("--model" "sonnet" "--no-auto-accept-architect")) ;; add --no-auto-commits if you don't want it
;;   ;; (setenv "ANTHROPIC_API_KEY" anthropic-api-key)
;;   ;; Or chatgpt model
;;   (setq aider-args '("--model" "o4-mini"))
;;   (if (file-exists-p "~/.emacs.aider.el")
;;       ;; (setenv "OPENAI_API_KEY" <your-openai-api-key>)
;;       (load "~/.emacs.aider.el") 
;;   )
  
;;   ;; (setenv "OPENAI_API_KEY" <your-openai-api-key>)
;;   ;; Or use your personal config file
;;   ;; (setq aider-args `("--config" ,(expand-file-name "~/.aider.conf.yml")))
;;   ;; ;;
;;   ;; Optional: Set a key binding for the transient menu
;;   ;;(global-set-key (kbd "C-c a") 'aider-transient-menu) ;; for wider screen
;;   (global-set-key (kbd "s-a") 'aider-transient-menu) ;; for wider screen
;;   ;; or use aider-transient-menu-2cols / aider-transient-menu-1col, for narrow screen
;;   (aider-magit-setup-transients) ;; add aider magit function to magit menu
;;   ;; auto revert buffer
;;   (global-auto-revert-mode 1)
;;   (auto-revert-mode 1))
