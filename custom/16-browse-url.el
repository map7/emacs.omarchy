;;; -*- lexical-binding: t; -*-
;;; Opening links and other external programs from the daemon.

;; The Emacs daemon is started before the Wayland compositor, so its own
;; environment has no WAYLAND_DISPLAY.  Graphical frames still work,
;; because emacsclient supplies the display when it creates them, but
;; every program Emacs launches (Firefox from a link, dired-open, ...)
;; inherits the daemon's environment and finds no display.  Adopt the
;; display variables from the emacsclient that creates each frame, so a
;; compositor restart picks up the new socket by itself.
(defun adopt-client-display-env ()
  "Copy display variables from the emacsclient that created this frame."
  (let* ((client (frame-parameter nil 'client))
         (env (and (processp client) (process-get client 'env))))
    (dolist (var '("WAYLAND_DISPLAY" "DISPLAY" "XDG_RUNTIME_DIR"))
      (let ((value (getenv-internal var env)))
        (when value (setenv var value))))))

(add-hook 'server-after-make-frame-hook #'adopt-client-display-env)

;; Open links with xdg-open, which honours the desktop default browser
;; (firefox.desktop here).  `browse-url-default-browser' is not usable on
;; this build: pgtk reports GDK's display name ("wayland-0") as the
;; frame's `display' parameter rather than the socket name, and
;; `browse-url-firefox' passes that on as WAYLAND_DISPLAY, so Firefox
;; looks for a socket that does not exist.  `browse-url-xdg-open' uses
;; the environment as-is.
(setq browse-url-browser-function #'browse-url-xdg-open)
