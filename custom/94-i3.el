;; Start a server  -*- lexical-binding: t; -*-
;; Only if one is not already up: a daemon starts its own server, and a second
;; Emacs calling `server-start' unconditionally warns that it cannot take over
;; the running server's socket.
(require 'server)
(unless (server-running-p)
  (server-start))

;; to start other emacs windows in i3 use 's-d emacsclient -c'


