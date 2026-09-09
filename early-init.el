;;; early-init.el --- Pre-startup configuration  -*- lexical-binding: t; -*-

;; Emacs runs `package-activate-all' between early-init.el and init.el, while
;; `package-user-dir' is still ~/.emacs.d/elpa - chemacs only repoints it at the
;; profile afterwards, when it loads init.el. Anything sitting in ~/.emacs.d/elpa
;; is therefore activated first and shadows this profile's own copy, because
;; `package-activate' skips a package that is already activated.
;;
;; That silently pinned 17 packages to the shared chemacs directory, several of
;; them years out of date. web-server 0.1.2 (2013) won over the 20210708 copy
;; here, which is what the org-ehtml server on port 8888 was running on, and
;; where the obsolete `case'/`ecase' warnings at startup came from.
;;
;; init.el sets this too, but by then activation has already happened. It has to
;; be here. chemacs loads <profile>/early-init.el before Emacs activates packages.

(setq package-enable-at-startup nil)

;;; early-init.el ends here
