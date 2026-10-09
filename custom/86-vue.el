;;; 86-vue.el --- Vue.js 3 single-file components  -*- lexical-binding: t; -*-

;;; Commentary:

;; `.vue' SFCs open in `vue3-mode', a polymode.  The file's own buffer is the
;; host, in `vue-html-mode' for the markup; each <script>/<style>/<i18n> block
;; gets an indirect buffer whose major mode comes from the block's `lang'
;; attribute.  So a <script setup lang="ts"> block is edited in real
;; `typescript-mode' rather than one flat template mode, which is why this is
;; `vue3-mode' and not `web-mode' (83-web-mode.el deliberately leaves `.vue'
;; alone).
;;
;; Two consequences worth knowing before changing anything here:
;;
;;   - The host buffer's `major-mode' is `vue-html-mode', never `vue3-mode'.
;;     Anything keyed off a major mode (a flycheck checker, say) has to name
;;     `vue-html-mode' to reach a `.vue' buffer.
;;
;;   - Polymode installs a block's major mode without running that mode's own
;;     hooks, so nothing on `prog-mode-hook' reaches a block buffer.  Per-block
;;     setup belongs on `polymode-init-inner-hook' instead.
;;
;;   - The <script> blocks use their own major modes, derived from js-mode and
;;     typescript-mode, purely so eglot can be told they are Vue.  See
;;     `map7/vue-js-block-mode' below.

;;; Code:

;; vue3-mode's innermodes call their major mode by name, so a block whose mode
;; is not installed signals void-function and loses the whole buffer.  Two of
;; them name modes this config does not have; alias them to the equivalents
;; Emacs ships, before any `.vue' buffer asks.
(unless (fboundp 'json-mode)
  (defalias 'json-mode 'js-json-mode))          ; <i18n> and <i18n lang="json">
(unless (fboundp 'typescript-tsx-mode)
  (defalias 'typescript-tsx-mode 'tsx-ts-mode)) ; <script lang="tsx">
;; <template lang="pug">, "jade" and "slim" are left unmapped on purpose:
;; those are separate packages (pug-mode, slim-mode).  Install one if a
;; component ever turns up using it - there is no sane stand-in here.

(defconst map7/vue-prettier-config-files
  '(".prettierrc" ".prettierrc.json" ".prettierrc.yml" ".prettierrc.yaml"
    ".prettierrc.json5" ".prettierrc.js" ".prettierrc.cjs" ".prettierrc.mjs"
    ".prettierrc.toml" "prettier.config.js" "prettier.config.cjs"
    "prettier.config.mjs")
  "File names that mean a project has opted into prettier.")

(defun map7/vue-prettier-project-p ()
  "Non-nil if this file's project opts into prettier.
True when a prettier config sits above the file, or when the nearest
package.json names prettier in any of its dependency or config keys."
  (let ((dir (or (and buffer-file-name (file-name-directory buffer-file-name))
                 default-directory)))
    (or (seq-some (lambda (name) (locate-dominating-file dir name))
                  map7/vue-prettier-config-files)
        (let ((pkg (locate-dominating-file dir "package.json")))
          (when pkg
            (with-temp-buffer
              (insert-file-contents (expand-file-name "package.json" pkg))
              (goto-char (point-min))
              (re-search-forward "\"prettier\"" nil t)))))))

(defun map7/vue-maybe-prettier ()
  "Enable `prettier-js-mode' only in a project that opts into prettier."
  (when (map7/vue-prettier-project-p)
    (prettier-js-mode 1)))

(define-derived-mode map7/vue-js-block-mode js-mode "Vue/JS"
  "A <script> block of a Vue SFC, in JavaScript.")

(define-derived-mode map7/vue-ts-block-mode typescript-mode "Vue/TS"
  "A <script> block of a Vue SFC, in TypeScript.")

(defconst map7/vue-script-modes
  '(map7/vue-js-block-mode map7/vue-ts-block-mode)
  "Modes used for a <script> block, and the ones worth a language server.
These exist only so the eglot entry below can carry `:language-id \"vue\"'
without putting it on plain js-mode and typescript-mode buffers too, which
would send every ordinary .js and .ts file to the Vue server.")

(defun map7/vue-typescript-plugin ()
  "Return the directory of @vue/typescript-plugin, or nil.
Prefers one the project installed, and otherwise the copy that ships inside
the globally installed @vue/language-server."
  (let* ((here (or buffer-file-name default-directory))
         (root (locate-dominating-file here "node_modules"))
         (local (and root (expand-file-name
                           "node_modules/@vue/typescript-plugin" root)))
         (server (executable-find "vue-language-server"))
         ;; .../@vue/language-server/bin/vue-language-server.js -> the package root
         (bundled (and server
                       (expand-file-name
                        "../../node_modules/@vue/typescript-plugin"
                        (file-name-directory (file-truename server))))))
    (cond ((and local (file-directory-p local)) local)
          ((and bundled (file-directory-p bundled)) bundled))))

(defun map7/vue-eglot-contact (&rest _)
  "Return the language server command for a Vue SFC <script> block.
This is typescript-language-server with @vue/typescript-plugin loaded, not
vue-language-server.  vue-language-server 3.x does the TypeScript half of its
work by asking the client to relay requests to a tsserver running the same
plugin, using `tsserver/request' notifications that eglot does not implement -
it connects and then answers every completion request with nothing.  Loading
the plugin into tsserver directly puts the answers back where eglot can see
them."
  (let ((plugin (map7/vue-typescript-plugin)))
    (append '("typescript-language-server" "--stdio")
            (when plugin
              (list :initializationOptions
                    (list :plugins
                          (vector (list :name "@vue/typescript-plugin"
                                        :location plugin
                                        :languages (vector "vue")))))))))

(defun map7/vue-init-block ()
  "Set up one block of a Vue SFC, from `polymode-init-inner-hook'.
Runs in the block's own indirect buffer with `major-mode' set to that
block's mode."
  (when (eq (eieio-oref pm/polymode '-minor-mode) 'vue3-mode)
    ;; `js-indent-level' and `css-indent-offset' are already 2 (87-javascript.el,
    ;; 79-css.el).  `typescript-mode' defaults to 4, so even a <script lang="ts">
    ;; block up with the markup around it.  Buffer-local, so plain .ts files keep
    ;; whatever 63-tide.el gives them.
    (setq-local typescript-indent-level 2)
    ;; Lint the component as a whole instead, from the host buffer.  A checker
    ;; run here sees one fragment - a <script setup> body with no imports
    ;; resolved, a nested scss rule with no selector - and reports errors that
    ;; are not in the file.
    (when (bound-and-true-p flycheck-mode)
      (flycheck-mode -1))
    ;; Attach a language server to the code blocks, so completion in a <script>
    ;; block offers what a symbol actually has on it rather than words scraped
    ;; out of the file.  Only the script blocks: a <style> or <i18n> block has
    ;; nothing for vue-language-server to say, and every extra buffer that
    ;; attaches opens the same file at the server again.
    ;; Polymode installs a block's major mode without running that mode's own
    ;; hooks, so anything hung on `prog-mode-hook' never reaches these buffers.
    ;; Pull the pieces that matter in by hand.
    (when (fboundp 'map7/enable-reindent-closing-delimiter)
      (map7/enable-reindent-closing-delimiter))
    (when (and (memq major-mode map7/vue-script-modes)
               (fboundp 'eglot-ensure)
               (executable-find "typescript-language-server"))
      (eglot-ensure))))

(use-package vue3-mode
  :ensure t
  ;; The package's autoloads register `.vue' in `auto-mode-alist' but never
  ;; autoload the mode function itself, so without this `:mode' (which does
  ;; autoload it) visiting a `.vue' file fails and falls back to
  ;; fundamental-mode.
  :mode "\\.vue\\'"
  :init
  ;; Colour `{{ interpolations }}' in the template.
  (setq vue-html-color-interpolations t)
  :config
  (add-hook 'polymode-init-inner-hook #'map7/vue-init-block)

  ;; eslint with eslint-plugin-vue understands a whole `.vue' file, so it is the
  ;; one checker that belongs on the host buffer.  Named `vue-html-mode' because
  ;; that is what the host buffer's `major-mode' is - see the Commentary.
  (with-eval-after-load 'flycheck
    (flycheck-add-mode 'javascript-eslint 'vue-html-mode))

  ;; Send the <script> innermodes to our own block modes instead of plain
  ;; js-mode / typescript-mode.  Everything else about them stays as the package
  ;; defined it.
  (dolist (innermode '(vue3-script-innermode
                       vue3-script-es6-innermode
                       vue3-script-js-innermode
                       vue3-script-javascript-innermode))
    (when (boundp innermode)
      (eieio-oset (symbol-value innermode) 'mode 'map7/vue-js-block-mode)))
  (dolist (innermode '(vue3-script-ts-innermode
                       vue3-script-typescript-innermode))
    (when (boundp innermode)
      (eieio-oset (symbol-value innermode) 'mode 'map7/vue-ts-block-mode)))

  ;; `:language-id "vue"' is what makes @vue/typescript-plugin take the file on.
  ;; It is safe to state here because these modes are only ever used for a block
  ;; of a .vue file.
  (with-eval-after-load 'eglot
    (add-to-list 'eglot-server-programs
                 (cons (mapcar (lambda (m) (list m :language-id "vue"))
                               map7/vue-script-modes)
                       #'map7/vue-eglot-contact)))

  ;; Prefer a project-local eslint, same as the TS modes.  `my/use-local-eslint'
  ;; comes from 63-tide.el, which init.el loads first.
  (when (fboundp 'my/use-local-eslint)
    (add-hook 'vue3-mode-hook #'my/use-local-eslint))

  ;; Format on save, as 63-tide.el does for js/ts - but only where the project
  ;; asks for it.  prettier rewrites the whole file, so switching it on for a
  ;; component tree that was never prettier-formatted turns the next save into a
  ;; few hundred lines of unrelated diff.  A project that wants prettier says so,
  ;; so look for it being said.
  (when (fboundp 'prettier-js-mode)
    (add-hook 'vue3-mode-hook #'map7/vue-maybe-prettier)))

(provide '86-vue)
;;; 86-vue.el ends here
