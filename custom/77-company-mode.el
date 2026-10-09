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

;;; Completion that triggers on a dot, not after three more characters.

;; `company-minimum-prefix-length' defaults to 3, so `DateTime.' showed nothing
;; until three characters of the member name were typed.  Two separate things
;; have to change for a popup right after the dot:
;;
;;   - the threshold has to come down, and
;;   - something has to start company at all.  After a `.' the prefix company
;;     sees is empty, so no threshold, not even 1, will fire by itself.
;;
;; Both are scoped to `prog-mode' buffers.  Globally, a 1-character threshold
;; makes company pop up constantly while writing prose in org and text buffers.

(defun map7/company-eager-completion ()
  "Complete from the first character typed, in this buffer only."
  (setq-local company-minimum-prefix-length 1))

(defun map7/company-begin-after-dot ()
  "Start completion as soon as a `.' is typed, with no prefix yet.
On `post-self-insert-hook', so it sees the dot the moment it lands."
  (when (and (bound-and-true-p company-mode)
             (not (company-in-string-or-comment))
             (eq (char-before) ?.)
             (not (eq (char-before (1- (point))) ?.)) ; not `..' or a `...' range
             ;; A dot straight after whitespace or nothing is a decimal point or
             ;; punctuation, not member access.
             (save-excursion
               (forward-char -1)
               (not (looking-back "[[:space:]]\\|^" 1))))
    (company-manual-begin)))

(defun map7/company-setup-prog-buffer ()
  "Turn on eager, dot-triggered completion in a code buffer."
  (map7/company-eager-completion)
  (add-hook 'post-self-insert-hook #'map7/company-begin-after-dot nil t))

(add-hook 'prog-mode-hook #'map7/company-setup-prog-buffer)

;; Polymode runs a Vue SFC's <script> block in an indirect buffer, and that
;; buffer's own mode hooks fire before polymode finishes wiring it up (see
;; 86-vue.el).  `polymode-init-inner-hook' runs once it is complete, so hook the
;; block buffers there as well.
(with-eval-after-load 'polymode
  (add-hook 'polymode-init-inner-hook #'map7/company-setup-prog-buffer))
