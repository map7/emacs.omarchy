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


;;;; Pulling remote changes automatically
;;
;; Google Drive can push change notifications, but only to a public HTTPS
;; endpoint on a domain verified in Search Console, with channels that
;; expire every 24 hours and have to be renewed.  That is a lot of moving
;; parts for one workstation behind NAT, so this polls instead.
;;
;; A check costs one Drive files.get for four fields.  Only when the remote
;; headRevisionId differs from the one gdocs recorded does it fetch the
;; document, and that fetch goes through gdocs' own three-way merge, so
;; local edits survive and only a real clash opens the conflict buffer.
;;
;; Three triggers: a timer while the buffer is on screen, switching to the
;; buffer, and Emacs regaining focus, which is the usual moment after
;; editing the doc in a browser.  Opening a linked file is already covered
;; by `gdocs-auto-pull-on-open' above.

(defcustom my/gdocs-poll-interval 60
  "Seconds between remote revision checks for on-screen gdocs buffers.
Set to nil to rely on the focus and buffer-switch triggers alone."
  :type '(choice (const :tag "No timer" nil) integer)
  :group 'gdocs)

(defcustom my/gdocs-check-throttle 15
  "Minimum seconds between remote revision checks of the same buffer.
Stops the focus and window-selection triggers from firing a request
every time you tab back and forth."
  :type 'integer
  :group 'gdocs)

(defcustom my/gdocs-poll-visible-only t
  "When non-nil, only check buffers currently shown in a window."
  :type 'boolean
  :group 'gdocs)

(defcustom my/gdocs-poll-skip-modified t
  "When non-nil, skip buffers with unsaved changes.
A pull would merge rather than clobber them, but a timer is a poor
moment to be handed a conflict buffer.  Save, which pushes, or pull by
hand instead."
  :type 'boolean
  :group 'gdocs)

(defvar my/gdocs--poll-timer nil
  "Repeating timer created by `my/gdocs-auto-pull-mode'.")

(defvar-local my/gdocs--last-check nil
  "`float-time' of the last remote revision check in this buffer.")

(defun my/gdocs--checkable-p ()
  "Return non-nil if the current buffer is worth asking Drive about."
  (and (bound-and-true-p gdocs-mode)
       (bound-and-true-p gdocs-sync--document-id)
       (not (and my/gdocs-poll-skip-modified (buffer-modified-p)))))

(defun my/gdocs--check-remote ()
  "Ask Drive whether the linked doc moved on, and pull if it did."
  (when (my/gdocs--checkable-p)
    (setq my/gdocs--last-check (float-time))
    (let ((buf (current-buffer)))
      (gdocs-api-get-file-metadata
       gdocs-sync--document-id
       (lambda (metadata)
         (when (buffer-live-p buf)
           (with-current-buffer buf
             (let ((remote (alist-get 'headRevisionId metadata)))
               (unless (gdocs-sync--revision-matches-p remote)
                 (message "gdocs: %s changed remotely, pulling" (buffer-name))
                 ;; Internal, so fall back to the command if it ever goes
                 ;; away.  `gdocs-sync-pull' repeats the metadata request.
                 (if (fboundp 'gdocs-sync--fetch-document-for-pull)
                     (gdocs-sync--fetch-document-for-pull remote)
                   (gdocs-sync-pull)))))))
       gdocs-sync--account))))

(defun my/gdocs--check-remote-throttled ()
  "Check for remote changes unless this buffer was checked recently."
  (when (or (null my/gdocs--last-check)
            (> (- (float-time) my/gdocs--last-check) my/gdocs-check-throttle))
    (my/gdocs--check-remote)))

(defun my/gdocs--buffers-to-check ()
  "Return the buffers a poll should consider."
  (if my/gdocs-poll-visible-only
      (delete-dups (mapcar #'window-buffer (window-list-1 nil 'nomini t)))
    (buffer-list)))

(defun my/gdocs--poll ()
  "Check every candidate buffer for remote changes."
  (dolist (buf (my/gdocs--buffers-to-check))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (my/gdocs--check-remote-throttled)))))

(defun my/gdocs--on-window-selection (&optional _frame)
  "Check the newly selected window's buffer for remote changes."
  (let ((buf (window-buffer (selected-window))))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (my/gdocs--check-remote-throttled)))))

(defun my/gdocs--on-focus-change ()
  "Check when Emacs regains focus, the usual moment after a browser edit."
  (when (and (fboundp 'frame-focus-state) (frame-focus-state))
    (my/gdocs--on-window-selection)))

(define-minor-mode my/gdocs-auto-pull-mode
  "Pull Google Docs changes into linked org buffers as they appear."
  :global t
  :group 'gdocs
  (when my/gdocs--poll-timer
    (cancel-timer my/gdocs--poll-timer)
    (setq my/gdocs--poll-timer nil))
  (if my/gdocs-auto-pull-mode
      (progn
        (when my/gdocs-poll-interval
          (setq my/gdocs--poll-timer
                (run-with-timer my/gdocs-poll-interval my/gdocs-poll-interval
                                #'my/gdocs--poll)))
        (add-hook 'window-selection-change-functions
                  #'my/gdocs--on-window-selection)
        (add-function :after after-focus-change-function
                      #'my/gdocs--on-focus-change))
    (remove-hook 'window-selection-change-functions
                 #'my/gdocs--on-window-selection)
    (remove-function after-focus-change-function #'my/gdocs--on-focus-change)))

(my/gdocs-auto-pull-mode 1)


;;;; Keep imported tables aligned
;;
;; Google Docs tables arrive as valid but ragged org: the cells are right,
;; the pipes do not line up, and the rule row is a stub like |---+---+---|.
;; Org fixes that on TAB, so do it on the way in rather than by hand.
;;
;; Safe with respect to pushing: `org-table-align' only pads cells, which
;; the org parser trims, so the IR is byte-identical before and after.
;; Both install paths set their shadow copy from the buffer, and the
;; shadow is compared by content keys, so alignment produces no diff.

(defcustom my/gdocs-align-tables t
  "When non-nil, align org tables after importing or pulling a doc."
  :type 'boolean
  :group 'gdocs)

(defun my/gdocs--align-tables (&rest _)
  "Align every org table in the current buffer, keeping the file in step."
  (when (and my/gdocs-align-tables
             (derived-mode-p 'org-mode)
             (bound-and-true-p gdocs-sync--document-id))
    (let ((was-modified (buffer-modified-p))
          (inhibit-message t))
      (save-excursion
        (org-table-map-tables #'org-table-align t))
      ;; Both callers save before this advice runs, so write the alignment
      ;; out too.  Only when alignment is the sole change: an already
      ;; modified buffer holds edits that are the user's to save.
      (when (and buffer-file-name
                 (buffer-modified-p)
                 (not was-modified))
        (let ((gdocs-auto-push-on-save nil)
              (before-save-hook nil)
              (after-save-hook nil))
          (save-buffer))))))

;; `gdocs--open-document-from-json' is the first import, and
;; `gdocs-sync--install-content' is every pull and merge afterwards.
(advice-add 'gdocs--open-document-from-json :after #'my/gdocs--align-tables)
(advice-add 'gdocs-sync--install-content :after #'my/gdocs--align-tables)
