;;; init.el --- Emacs configuration backbone  -*- lexical-binding: t; -*-

;;; Commentary:
;;; All Emacs configuration starts from this file.

;;; Code:

;;;; Performance
(add-to-list 'load-path (expand-file-name "custom" user-emacs-directory))
(load "102-performance.el")

;;;; Package management
(require 'package)
(setq package-enable-at-startup nil)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/"))
(add-to-list 'package-archives '("gnu" . "https://elpa.gnu.org/packages/"))
(add-to-list 'package-archives '("org" . "https://orgmode.org/elpa/"))

(load "external-plugins")
(add-to-list 'load-path (expand-file-name "external" user-emacs-directory))
(package-initialize)

(setq use-package-always-ensure t)

;; Setup straight
(defvar bootstrap-version)
(let ((bootstrap-file
       (expand-file-name
        "straight/repos/straight.el/bootstrap.el"
        (or (bound-and-true-p straight-base-dir)
            user-emacs-directory)))
      (bootstrap-version 7))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/radian-software/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

;;;; Package declarations
(use-package transient)
(use-package all-the-icons)
(use-package ansible)
(use-package clojure-mode)
(use-package crontab-mode)
(use-package circe)
(use-package company)
(use-package csv-mode)
(use-package crdt)
(use-package dired-open-with)
(use-package dumb-jump)
(use-package expand-region)
(use-package findr)
(use-package ledger-mode)
(use-package markdown-mode)
(use-package org-noter)
(use-package paradox  :config
  (unless (assoc-string "source" paradox--package-count)
    (push '("source" . 0) paradox--package-count)))
(use-package picpocket :bind ("M-p" . picpocket))
(use-package sudo-edit)
(use-package switch-window)
;; Deferred: loading vterm eagerly prompts to compile `vterm-module' at
;; startup, which blocks a daemon start.  Load it on first use instead.
(use-package vterm :defer t :commands (vterm vterm-other-window))
(use-package tramp-term)
(use-package restclient)
(use-package xkcd)
(use-package dockerfile-mode)
(use-package disk-usage)
(use-package rg)
(use-package wgrep)
(use-package total-lines
  :config (global-total-lines-mode))

;; Passwords
(use-package keepass-mode)
(use-package pinentry
  :init
  (pinentry-start)
  :config
  (setq epa-pinentry-mode 'loopback))
(use-package pass)

;; AI
(use-package claude-code
  :vc (:url "https://github.com/stevemolitor/claude-code.el"
       :rev :newest
       :branch "main"))

;; Other langs
(use-package php-mode)

;; Ruby related
(use-package enh-ruby-mode)
(use-package ruby-refactor)

;; Org related
(use-package org-cliplink)
(use-package org-clock-csv)
(use-package org-clock-today)

;;;; 4gl mode
(add-to-list 'load-path (expand-file-name "external/4gl-mode-master" user-emacs-directory))
(require '4gl-mode)

;;;; Custom config files

;;--------------------------------------------------------------------------------
;;-Base emacs related (0-39)
;;--------------------------------------------------------------------------------
(load "shell-env.el")
(load "00-common-setup.el")
(load "01-pdf-tools.el")
(load "02-bpr.el")
(load "03-async.el")
(load "04-packages.el")
(load "05-scroll-settings.el")
(load "06-togetherly.el")
(load "07-dired.el")
(load "08-nlinum.el")
(load "09-real-auto-save.el")
(load "10-multi-term.el")
(load "11-eshell.el")
(load "12-projectile.el")
(load "15-winner-mode.el")
(load "17-emacs-server.el")
(load "18-flyspell.el")
(load "22-epa-file.el")
(load "33-ivy.el")
(load "34-windmove.el")
(load "35-paperless.el")
(load "36-nov.el")
(load "38-elfeed.el")
(load "19-youtube-music.el")
(load "24-midi.el")

;;--------------------------------------------------------------------------------
;;-Org-mode related (40-49)
;;--------------------------------------------------------------------------------
(load "40-org.el")
(load "42-org-expiry.el")
(load "43-revealjs.el")
(load "44-org-publish.el")
(load "45-org-easydraw.el")
(load "46-whisper.el")
(load "invoice_quickbooks.el")

;;--------------------------------------------------------------------------------
;;-Programming tools (50-69)
;;--------------------------------------------------------------------------------
(load "50-multiple-cursors.el")
(load "51-undo-tree.el")
(load "52-rainbow.el")
(load "53-magit.el")
(load "54-yasnippet.el")
(load "55-rinari.el")
(load "59-highlight-parentheses.el")
(load "60-yafolding.el")
(load "61-ruby-refactor.el")
(load "62-robe.el")
(load "63-tide.el")
(load "65-iedit.el")
(load "66-flycheck.el")
(load "67-tags.el")
(load "68-seeing-is-believing.el")
(load "69-javascript.el")
(load "70-ai.el")

;;--------------------------------------------------------------------------------
;;-Programming modes (75-94)
;;--------------------------------------------------------------------------------
(load "75-scss-mode.el")
(load "76-rspec_mode.el")
(load "77-company-mode.el")
(load "78-haml.el")
(load "79-css.el")
(load "80-coffeescript.el")
(load "81-ruby.el")
(load "82-xml.el")
(load "83-web-mode.el")
(load "84-html-mode.el")
(load "85-yaml_mode.el")
(load "87-javascript.el")
(load "88-arduino_mode.el")
(load "89-python.el")
(load "89-rust.el")

;;--------------------------------------------------------------------------------
;;-EXWM, appearance and shortcut keys
;;--------------------------------------------------------------------------------
(load "94-i3.el")
(load "95-resize-buffer.el")
(load "97-shortcuts.el")

;;;; Appearance
;; 100-theme.el intentionally not loaded here - the Omarchy theme is applied
;; by omarchy.el at the end of this file. Use `M-x omarchy-apply-theme' to reapply.
(load "101-modeline.el")

;; Frame size
(add-to-list 'default-frame-alist '(height . 40))
(add-to-list 'default-frame-alist '(width . 150))

;;;; Optional/conditional loads
(let ((f (expand-file-name ".emacs.autostart.el" user-emacs-directory)))
  (when (file-exists-p f) (load f)))

(let ((f (expand-file-name ".emacs.paradox.el" user-emacs-directory)))
  (when (file-exists-p f) (load f)))

(let ((f (expand-file-name ".emacs.workspace.el" user-emacs-directory)))
  (when (file-exists-p f) (load f)))

(let ((f (expand-file-name ".emacs.custom.el" user-emacs-directory)))
  (when (file-exists-p f) (load f)))

;;;; Misc
(put 'downcase-region 'disabled nil)

;;; init.el ends here
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(bookmark-default-file "~/Sync/emacs-bookmarks")
 '(dired-open-extensions
   '(("jpg" . "shotwell") ("jpeg" . "shotwell") ("gif" . "shotwell")
     ("bmp" . "shotwell") ("png" . "shotwell") ("wp" . "libreoffice")
     ("ott" . "libreoffice") ("odt" . "libreoffice")
     ("odf" . "libreoffice") ("ods" . "libreoffice")
     ("ots" . "libreoffice") ("xcf" . "gimp") ("svg" . "inkscape")
     ("kdbx" . "keepassxc") ("xls" . "libreoffice")
     ("doc" . "libreoffice") ("dot" . "libreoffice")
     ("pub" . "libreoffice") ("odg" . "libreoffice")
     ("ppt" . "libreoffice") ("mp4" . "mplayer")
     ("netmap" . "java -jar ~/bin/jNetMap.jar $1")
     ("glabels" . "glabels-3") ("abw" . "libreoffice")
     ("JPG" . "shotwell")))
 '(dired-open-functions '(dired-open-by-extension dired-open-subdir ignore))
 '(erc-modules
   '(autojoin button completion fill irccontrols list log match menu
              move-to-prompt netsplit networks noncommands notify
              readonly ring stamp track))
 '(flycheck-coffee-coffeelint-executable "/opt/node-v5.5.0-linux-x64/bin/coffeelint")
 '(flycheck-coffeelintrc "~/coffeelint.json")
 '(flycheck-javascript-eslint-executable "/opt/node-v5.5.0-linux-x64/bin/eslint")
 '(flycheck-ruby-rubocop-executable
   "/home/map7/.local/share/mise/installs/ruby/3.4.5/bin/rubocop")
 '(org-agenda-files
   '("/home/map7/org/20130222.org"
     "/home/map7/org/Getting Started with Orgzly.org"
     "/home/map7/org/aad.org" "/home/map7/org/advice.org"
     "/home/map7/org/ai.org" "/home/map7/org/alchester.org"
     "/home/map7/org/amanda-bishop-framework-notebook.org"
     "/home/map7/org/amanda.org" "/home/map7/org/anchovies.org"
     "/home/map7/org/assistance_and_access_bill_2018.org"
     "/home/map7/org/asus_transformer_tf300t_tablet.org"
     "/home/map7/org/ava.org" "/home/map7/org/baby.org"
     "/home/map7/org/bars.org" "/home/map7/org/bb-8.org"
     "/home/map7/org/bender.org" "/home/map7/org/bike.org"
     "/home/map7/org/blog.org" "/home/map7/org/bluray.org"
     "/home/map7/org/books.org" "/home/map7/org/brands.org"
     "/home/map7/org/breezeviti.org" "/home/map7/org/brother.org"
     "/home/map7/org/cafes.org" "/home/map7/org/camping.org"
     "/home/map7/org/car.org" "/home/map7/org/cars.org"
     "/home/map7/org/cat_mccain.org" "/home/map7/org/chip.org"
     "/home/map7/org/chiptunes.org"
     "/home/map7/org/chocolate_bars.org"
     "/home/map7/org/cholesterol.org" "/home/map7/org/cider.org"
     "/home/map7/org/coffee.org" "/home/map7/org/cool_things.org"
     "/home/map7/org/covid-19.org" "/home/map7/org/cubox.org"
     "/home/map7/org/d&d.org" "/home/map7/org/dad.org"
     "/home/map7/org/dale.org" "/home/map7/org/danch.org"
     "/home/map7/org/data_retention.org" "/home/map7/org/deck.org"
     "/home/map7/org/digdug.org" "/home/map7/org/dinner.org"
     "/home/map7/org/donuts.org" "/home/map7/org/dvd.org"
     "/home/map7/org/ebay.org" "/home/map7/org/ebooks.org"
     "/home/map7/org/ecoprint.org" "/home/map7/org/electronics.org"
     "/home/map7/org/enocean.org"
     "/home/map7/org/ethical_companies.org"
     "/home/map7/org/flipper_zero.org" "/home/map7/org/flying.org"
     "/home/map7/org/free_wifi.org" "/home/map7/org/friends.org"
     "/home/map7/org/funny.org" "/home/map7/org/games.org"
     "/home/map7/org/gary.org" "/home/map7/org/gas.org"
     "/home/map7/org/geraldine.org" "/home/map7/org/gifs.org"
     "/home/map7/org/goev.org"
     "/home/map7/org/goev_auto_charge_article.org"
     "/home/map7/org/gpg_keys.org" "/home/map7/org/hal9000.org"
     "/home/map7/org/health.org" "/home/map7/org/heather_powell.org"
     "/home/map7/org/hole.org" "/home/map7/org/holiday.org"
     "/home/map7/org/home_25_ironbark.org"
     "/home/map7/org/home_5_ironbark.org"
     "/home/map7/org/home_daphne.org"
     "/home/map7/org/home_firewall.org" "/home/map7/org/home_food.org"
     "/home/map7/org/home_lex.org" "/home/map7/org/home_nas.org"
     "/home/map7/org/home_power.org" "/home/map7/org/home_wifi.org"
     "/home/map7/org/homelab.org" "/home/map7/org/ideas.org"
     "/home/map7/org/inbox.org" "/home/map7/org/initial_d.org"
     "/home/map7/org/insurance.org" "/home/map7/org/jack.org"
     "/home/map7/org/japan.org" "/home/map7/org/jawbone_jambox.org"
     "/home/map7/org/joe.org" "/home/map7/org/joe_debates.org"
     "/home/map7/org/kids.org" "/home/map7/org/kindle.org"
     "/home/map7/org/learning.org" "/home/map7/org/lego.org"
     "/home/map7/org/lend.org" "/home/map7/org/lenovo_n20_deckard.org"
     "/home/map7/org/leostick.org" "/home/map7/org/linkt_citylink.org"
     "/home/map7/org/linux.conf.au.org" "/home/map7/org/luca.org"
     "/home/map7/org/lunch.org" "/home/map7/org/makey_makey.org"
     "/home/map7/org/me.org" "/home/map7/org/medibank.org"
     "/home/map7/org/melbjs.org" "/home/map7/org/minimalism.org"
     "/home/map7/org/mlug contact.org" "/home/map7/org/mlug.org"
     "/home/map7/org/mlug_screen.org" "/home/map7/org/money.org"
     "/home/map7/org/motors.org" "/home/map7/org/movie_streaming.org"
     "/home/map7/org/movies.org" "/home/map7/org/music.org"
     "/home/map7/org/myki.org" "/home/map7/org/nan.org"
     "/home/map7/org/news.org" "/home/map7/org/ninjablocks.org"
     "/home/map7/org/notes.org" "/home/map7/org/nsa.org"
     "/home/map7/org/ollama.org" "/home/map7/org/orders.org"
     "/home/map7/org/pCorePlayer.org" "/home/map7/org/padrino.org"
     "/home/map7/org/parents.org" "/home/map7/org/party.org"
     "/home/map7/org/people.org" "/home/map7/org/personal_email.org"
     "/home/map7/org/piano.org" "/home/map7/org/pico.org"
     "/home/map7/org/pihole.org"
     "/home/map7/org/pikvm_mark_instructions.org"
     "/home/map7/org/planes.org" "/home/map7/org/pocket_chip.org"
     "/home/map7/org/pope_family.org" "/home/map7/org/powell.org"
     "/home/map7/org/prams.org" "/home/map7/org/presentation.org"
     "/home/map7/org/presents.org" "/home/map7/org/publishable.co.org"
     "/home/map7/org/publishing_solutions.org"
     "/home/map7/org/questions_for_joe.org"
     "/home/map7/org/raspberry_pi.org"
     "/home/map7/org/real_estate.org" "/home/map7/org/restaurant.org"
     "/home/map7/org/retailers.org" "/home/map7/org/robot_vacuum.org"
     "/home/map7/org/robots.org" "/home/map7/org/roof_racks.org"
     "/home/map7/org/roro.org" "/home/map7/org/rss_readers.org"
     "/home/map7/org/scary_tech.org" "/home/map7/org/series.org"
     "/home/map7/org/shoes.org" "/home/map7/org/shopping.org"
     "/home/map7/org/sister.org" "/home/map7/org/soundbars.org"
     "/home/map7/org/squash.org" "/home/map7/org/staffreview.org"
     "/home/map7/org/starcraft.org" "/home/map7/org/startrek.org"
     "/home/map7/org/steam.org" "/home/map7/org/steam_controller.org"
     "/home/map7/org/sylvana.org" "/home/map7/org/tax.org"
     "/home/map7/org/temp.org" "/home/map7/org/tents.org"
     "/home/map7/org/test.org" "/home/map7/org/test_reveal.org"
     "/home/map7/org/thoughts.org" "/home/map7/org/torc.org"
     "/home/map7/org/torrents.org" "/home/map7/org/train.org"
     "/home/map7/org/tv.org" "/home/map7/org/tv_shows.org"
     "/home/map7/org/tv_units.org" "/home/map7/org/up_squared.org"
     "/home/map7/org/vesti.org" "/home/map7/org/vinocellar.org"
     "/home/map7/org/wandboard.org" "/home/map7/org/wearable.org"
     "/home/map7/org/whisky.org" "/home/map7/org/willow.org"
     "/home/map7/org/wines.org" "/home/map7/org/xbmc_ir_keycodes.org"
     "/home/map7/org/xmas.org" "/home/map7/org/xt.org"
     "/home/map7/org/business/michael/3d_printing.org"
     "/home/map7/org/business/michael/android.org"
     "/home/map7/org/business/michael/angelo.org"
     "/home/map7/org/business/michael/angular.org"
     "/home/map7/org/business/michael/ansible.org"
     "/home/map7/org/business/michael/asset_management.org"
     "/home/map7/org/business/michael/ato.org"
     "/home/map7/org/business/michael/backup.org"
     "/home/map7/org/business/michael/backup_gem.org"
     "/home/map7/org/business/michael/because_we_care.org"
     "/home/map7/org/business/michael/cameras.org"
     "/home/map7/org/business/michael/chris.org"
     "/home/map7/org/business/michael/cleantime.org"
     "/home/map7/org/business/michael/click3pl.org"
     "/home/map7/org/business/michael/dcre.org"
     "/home/map7/org/business/michael/digitech.org"
     "/home/map7/org/business/michael/digitech_website.org"
     "/home/map7/org/business/michael/dms.org"
     "/home/map7/org/business/michael/dunlop_&_piston.org"
     "/home/map7/org/business/michael/ebay.org"
     "/home/map7/org/business/michael/emacs.org"
     "/home/map7/org/business/michael/email.org"
     "/home/map7/org/business/michael/fabulous_catering.org"
     "/home/map7/org/business/michael/fastline.org"
     "/home/map7/org/business/michael/firefox.org"
     "/home/map7/org/business/michael/firewall.org"
     "/home/map7/org/business/michael/frank_caleandro.org"
     "/home/map7/org/business/michael/front.org"
     "/home/map7/org/business/michael/git.org"
     "/home/map7/org/business/michael/globalfashionservice.org"
     "/home/map7/org/business/michael/google_drive.org"
     "/home/map7/org/business/michael/govreports.org"
     "/home/map7/org/business/michael/insync.org"
     "/home/map7/org/business/michael/internet.org"
     "/home/map7/org/business/michael/joe_carlton.org"
     "/home/map7/org/business/michael/joe_farm.org"
     "/home/map7/org/business/michael/joe_notebook_airiam.org"
     "/home/map7/org/business/michael/joe_notebook_lenovo.org"
     "/home/map7/org/business/michael/john_farm.org"
     "/home/map7/org/business/michael/karbon.org"
     "/home/map7/org/business/michael/kenny_lay.org"
     "/home/map7/org/business/michael/kodi.org"
     "/home/map7/org/business/michael/kvm.org"
     "/home/map7/org/business/michael/libreoffice.org"
     "/home/map7/org/business/michael/lodgeit.org"
     "/home/map7/org/business/michael/logicaldoc.org"
     "/home/map7/org/business/michael/ltsp.org"
     "/home/map7/org/business/michael/marks_iga.org"
     "/home/map7/org/business/michael/meshcentral.org"
     "/home/map7/org/business/michael/mobile_apps.org"
     "/home/map7/org/business/michael/mobile_phones.org"
     "/home/map7/org/business/michael/mygovid.org"
     "/home/map7/org/business/michael/myob.org"
     "/home/map7/org/business/michael/nativescript.org"
     "/home/map7/org/business/michael/netflix.org"
     "/home/map7/org/business/michael/network.org"
     "/home/map7/org/business/michael/nucleus.org"
     "/home/map7/org/business/michael/online.com.org"
     "/home/map7/org/business/michael/pais.org"
     "/home/map7/org/business/michael/pais2.2.org"
     "/home/map7/org/business/michael/pais2.3.org"
     "/home/map7/org/business/michael/pais_legacy_invoice.org"
     "/home/map7/org/business/michael/pais_legacy_reporting.org"
     "/home/map7/org/business/michael/pais_legacy_xero.org"
     "/home/map7/org/business/michael/pais_website.org"
     "/home/map7/org/business/michael/paistram.org"
     "/home/map7/org/business/michael/pass.org"
     "/home/map7/org/business/michael/pdfcat.org"
     "/home/map7/org/business/michael/phone.org"
     "/home/map7/org/business/michael/power.org"
     "/home/map7/org/business/michael/practice_protect.org"
     "/home/map7/org/business/michael/printers.org"
     "/home/map7/org/business/michael/privitelli.org"
     "/home/map7/org/business/michael/prusa.org"
     "/home/map7/org/business/michael/publishing_solutions_website.org"
     "/home/map7/org/business/michael/qb_pais_legacy.org"
     "/home/map7/org/business/michael/quickbooks.org"
     "/home/map7/org/business/michael/rails.org"
     "/home/map7/org/business/michael/railscamp.org"
     "/home/map7/org/business/michael/railscamp24.org"
     "/home/map7/org/business/michael/reception_tv.org"
     "/home/map7/org/business/michael/remote_access.org"
     "/home/map7/org/business/michael/remote_working.org"
     "/home/map7/org/business/michael/report_craft.org"
     "/home/map7/org/business/michael/report_craft_marketing.org"
     "/home/map7/org/business/michael/report_craft_rails.org"
     "/home/map7/org/business/michael/roy_lenovo_p14s.org"
     "/home/map7/org/business/michael/scanner.org"
     "/home/map7/org/business/michael/sceona.org"
     "/home/map7/org/business/michael/security.org"
     "/home/map7/org/business/michael/selene.org"
     "/home/map7/org/business/michael/serial_server.org"
     "/home/map7/org/business/michael/spotify.org"
     "/home/map7/org/business/michael/syncthing.org"
     "/home/map7/org/business/michael/tableplus.org"
     "/home/map7/org/business/michael/tarantini_fortuna.org"
     "/home/map7/org/business/michael/ted_kirsh.org"
     "/home/map7/org/business/michael/thinlinc.org"
     "/home/map7/org/business/michael/thunderbird.org"
     "/home/map7/org/business/michael/tramontana.org"
     "/home/map7/org/business/michael/tramontana_backup.org"
     "/home/map7/org/business/michael/tramontana_dash.org"
     "/home/map7/org/business/michael/tramontana_website.org"
     "/home/map7/org/business/michael/uber.org"
     "/home/map7/org/business/michael/ups.org"
     "/home/map7/org/business/michael/venuebat.org"
     "/home/map7/org/business/michael/video_conferencing.org"
     "/home/map7/org/business/michael/webinar.org"
     "/home/map7/org/business/michael/windows.org"
     "/home/map7/org/business/michael/x2go.org"
     "/home/map7/org/business/michael/xero_pais_legacy.org"
     "/home/map7/org/projects/air_conditioner_automation.org"
     "/home/map7/org/projects/air_quality_meter_BME680.org"
     "/home/map7/org/projects/arcade_machine.org"
     "/home/map7/org/projects/auto_cat_feeder.org"
     "/home/map7/org/projects/baby_monitor.org"
     "/home/map7/org/projects/bike_computer.org"
     "/home/map7/org/projects/blind_controller.org"
     "/home/map7/org/projects/bloodbowl_scoreboard.org"
     "/home/map7/org/projects/boombox_amp_music_streamer.org"
     "/home/map7/org/projects/car_computer.org"
     "/home/map7/org/projects/dungeon_crawler.org"
     "/home/map7/org/projects/ebook_reader.org"
     "/home/map7/org/projects/emacs_foot_pedal.org"
     "/home/map7/org/projects/fan_remote_replacement.org"
     "/home/map7/org/projects/game_gear.org"
     "/home/map7/org/projects/garage_door_opener.org"
     "/home/map7/org/projects/garden_monitor.org"
     "/home/map7/org/projects/hack_belkin_wemo.org"
     "/home/map7/org/projects/home_automation.org"
     "/home/map7/org/projects/ip_camera.org"
     "/home/map7/org/projects/ir_blaster.org"
     "/home/map7/org/projects/maqueen_robot.org"
     "/home/map7/org/projects/mentoring.org"
     "/home/map7/org/projects/metal_warrior.org"
     "/home/map7/org/projects/mlug_video_recorder.org"
     "/home/map7/org/projects/mruby_electronics.org"
     "/home/map7/org/projects/mycroft_assistant.org"
     "/home/map7/org/projects/nas.org"
     "/home/map7/org/projects/neopixel_desk_lights.org"
     "/home/map7/org/projects/nerd_night.org"
     "/home/map7/org/projects/ocpp.org"
     "/home/map7/org/projects/pentesting.org"
     "/home/map7/org/projects/pi_tv_hat.org"
     "/home/map7/org/projects/piano_colour_strip.org"
     "/home/map7/org/projects/pikvm.org"
     "/home/map7/org/projects/port_barrell_level.org"
     "/home/map7/org/projects/power_usage_logging.org"
     "/home/map7/org/projects/radio.org"
     "/home/map7/org/projects/robot_arm.org"
     "/home/map7/org/projects/sick68_kb.org"
     "/home/map7/org/projects/smart_ring.org"
     "/home/map7/org/projects/smart_switch.org"
     "/home/map7/org/projects/temperature_alarm.org"
     "/home/map7/org/projects/template.org"
     "/home/map7/org/projects/tv_hat.org"
     "/home/map7/org/projects/voice_assistant.org"
     "/home/map7/org/projects/weather_station.org"
     "/home/map7/org/projects/wifi_ap.org"))
 '(org-stuck-projects '(":hard/+TODO" ("DONE" "REDUNDANT") nil ""))
 '(package-selected-packages
   '(slime-volleyball i3wm total-lines disk-usage system-packages
                      real-auto-save super-save org
                      mu4e-maildirs-extension goto-gem wgrep rg chess
                      dired-rainbow dired-narrow dired-ranger
                      dired-open dired-hacks-utils edit-indirect
                      pinentry ivy-pass sx backlight mw-thesaurus
                      company-statistics company counsel-org-clock
                      daemons bongo pass symon pocket-reader
                      pulseaudio-control yafolding nov rudel
                      dockerfile-mode treemacs dired-du nlinum-hl
                      pdf-tools spotify counsel-spotify
                      all-the-icons-ivy command-log-mode paperless
                      pacmacs slack crontab-mode tide xkcd
                      use-package-chords use-package flycheck
                      yasnippet yaml-mode web-mode undo-tree
                      twittering-mode tramp-term togetherly
                      switch-window sudo-edit spaceline scss-mode
                      ruby-refactor ruby-end ruby-electric rspec-mode
                      rsense robe rinari rbenv rainbow-mode
                      projectile-rails paradox pallet ox-reveal
                      org2blog org-clock-csv org-cliplink
                      org-attach-screenshot nlinum multiple-cursors
                      multi-term moe-theme markdown-mode magit
                      linum-off js2-mode
                      highlight-parentheses highlight-indentation
                      haml-mode grizzl expand-region enh-ruby-mode
                      diredful dired-details csv-mode coffee-mode
                      circe bpr ansible))
 '(package-vc-selected-packages
   '((youtube-music :url "https://github.com/emacsmirror/youtube-music")
     (claude-code :url
                  "https://github.com/stevemolitor/claude-code.el")))
 '(paperless-capture-directory "~/paperless/upload")
 '(paperless-root-directory "~/paperless/documents")
 '(paradox-automatically-star t)
 '(paradox-github-token t)
 '(safe-local-variable-values
   '((dired-omit-files . "\\.html\\'")
     (ruby-compilation-executable . "ruby")
     (ruby-compilation-executable . "ruby1.8")
     (ruby-compilation-executable . "ruby1.9")
     (ruby-compilation-executable . "rbx")
     (ruby-compilation-executable . "jruby")))
 '(undo-tree-visualizer-default-face nil)
 '(xcb:debug t))
;; The custom-set-faces block that used to live here hardcoded a dark palette
;; (default bg #000000, font-lock colours, magit colours, mode-line colours).
;; It is omitted so the Omarchy theme controls colours. The original is in
;; ~/.emacs.default/init.el if you ever want a face back.

;;;; Omarchy integration - theme, font, shell. Loaded last so it wins.
(load (expand-file-name "omarchy" user-emacs-directory))

;; omarchy.el puts `delete-trailing-whitespace' on before-save-hook globally.
;; That is wrong for this setup: real-auto-save-mode saves every org buffer
;; every 5 seconds, so a single keystroke rewrites whitespace across the whole
;; file, and ~/org is a Syncthing folder - the churn propagates to every device.
;; Drop it. Use `M-x delete-trailing-whitespace' by hand when you want it.
(remove-hook 'before-save-hook #'delete-trailing-whitespace)

;;; init.el ends here
