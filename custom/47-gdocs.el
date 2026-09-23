;; gdocs - two-way sync between org files and Google Docs  -*- lexical-binding: t; -*-
;; https://github.com/benthamite/gdocs
;; Manual: https://stafforini.com/notes/gdocs/
;;
;; Synced docs are ordinary org files under ~/org/gdocs/.  A linked file
;; carries a GDOCS_DOCUMENT_ID property, which switches on `gdocs-mode':
;; push on save, pull on open, and sync status in the modeline.
;;
;;   M-x gdocs-open        open a Google Doc (id or URL) as an org buffer
;;   M-x gdocs-create      publish the current org file as a new Google Doc
;;   M-x gdocs-menu        transient with every command and toggle
;;   C-c g p / C-c g l     push / pull, in a linked buffer
;;   C-c g s / C-c g o     sync status / open the doc in the browser
;;
;; Credentials are an OAuth client of type "Desktop app" created under
;; map7777@gmail.com, in a Cloud project with the Docs and Drive APIs
;; enabled.  It has to be "Desktop app": gdocs receives the authorization
;; code on http://localhost:<random port>, and only installed-app clients
;; may vary the port.  Id and secret are exported from ~/Sync/.zshenv.apps
;; (see shell-env.el) so they stay out of this repo.
;;
;; First run: M-x gdocs-authenticate, approve in the browser, and the
;; refresh token lands in ~/.emacs.omarchy/gdocs/tokens/map7777.json
;; (gitignored, mode 600).  After that it renews itself.

(defun my/gdocs-accounts ()
  "Build a `gdocs-accounts' value from the exported OAuth credentials.
Returns nil when the environment does not carry them, so a missing
secret leaves gdocs merely unauthenticated rather than breaking startup."
  (let ((id (shell-env-getenv "GDOCS_MAP7777_CLIENT_ID"))
        (secret (shell-env-getenv "GDOCS_MAP7777_CLIENT_SECRET")))
    (if (and id secret)
        `(("map7777" . ((client-id . ,id)
                        (client-secret . ,secret))))
      (message "gdocs: GDOCS_MAP7777_CLIENT_ID/SECRET unset, no account configured")
      nil)))

(use-package gdocs
  :vc (:url "https://github.com/benthamite/gdocs" :rev :newest)
  :commands (gdocs-open gdocs-create gdocs-authenticate gdocs-logout gdocs-menu)
  :custom
  (gdocs-directory (expand-file-name "gdocs/" org-directory))
  ;; Saving a linked buffer pushes; opening one pulls.  Both are async, and
  ;; a clash between local and remote edits opens the side-by-side merge
  ;; buffer rather than picking a winner.  Flip either from `gdocs-menu'.
  (gdocs-auto-push-on-save t)
  (gdocs-auto-pull-on-open t)
  :config
  (setq gdocs-accounts (my/gdocs-accounts)))

;; gdocs installs its own `org-mode-hook' entry, but only once it is loaded,
;; and `:commands' keeps it unloaded until one of those commands runs.  Check
;; for the property with a plain regexp search instead, so opening an
;; unrelated org file costs a buffer scan rather than pulling in gdocs, plz
;; and transient.  Loading gdocs enables the mode in org buffers that are
;; already open, this one included.
(defun my/gdocs-maybe-load ()
  "Load gdocs when the current org buffer is linked to a Google Doc."
  (when (and (not (featurep 'gdocs))
             (save-excursion
               (goto-char (point-min))
               (re-search-forward "^[ \t]*:GDOCS_DOCUMENT_ID:" nil t)))
    (require 'gdocs)))

(add-hook 'org-mode-hook #'my/gdocs-maybe-load)
