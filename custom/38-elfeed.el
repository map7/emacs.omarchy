;;; 38-elfeed.el --- Elfeed podcast/feed reader configuration  -*- lexical-binding: t; -*-

;;; Code:

(use-package elfeed
  :bind ("C-x w" . elfeed)
  :config
  (setq elfeed-feeds
        `(;; Podcasts - Accounting
          ("https://rss.buzzsprout.com/1761225.rss" podcast accounting)

          ;; Podcasts - Programming / Ruby
          ("https://rss.buzzsprout.com/1878319.rss" podcast ruby)                                        ; Code with Jason
          ("https://www.spreaker.com/show/6102073/episodes/feed" podcast ruby)                           ; Ruby Rogues
          ("https://rss.buzzsprout.com/2260490.rss" podcast ruby)                                        ; Remote Ruby
          ("https://bikeshed.thoughtbot.com/rss" podcast ruby)                                           ; The Bike Shed
          ("https://www.therubyonrailspodcast.com/rss" podcast ruby rails)                               ; Ruby on Rails Podcast

          ;; Podcasts - Tech / Software
          ("https://changelog.com/podcast/feed" podcast tech)                                            ; The Changelog
          ("https://feed.syntax.fm/rss" podcast tech webdev)                                             ; Syntax
          ("https://feeds.transistor.fm/practical-ai-machine-learning-data-science-llm" podcast tech ai) ; Practical AI

          ;; Triple R stopped publishing Byte Into IT as a podcast in Feb 2025,
          ;; but the show continues and the episodes stay on their site.
          ;; `rrr-feed' rebuilds a feed from the episode pages, with the
          ;; on-demand HLS stream as the enclosure.  rrr-feed.timer refreshes
          ;; it daily.  Absolute path, because file:// does not expand ~.
          (,(concat "file://" (expand-file-name "~/.local/share/rrr-feeds/byte-into-it.xml"))
           podcast tech)                                                                            ; Byte Into IT
          ;; The station's own feed stopped on 6 Feb 2025 but is still served,
          ;; and its 338 enclosures are real mp3s on S3, so it still carries the
          ;; whole back catalogue.  Between the two there is a gap from Feb 2025
          ;; to the start of RRR's on-demand window, which has audio nowhere.
          ("https://www.rrr.org.au/explore/podcasts/byte-into-it/feed.xml" podcast tech archive)    ; Byte Into IT (archive)

          ;; Podcasts - Linux / Self-hosting
          ("https://feeds.jupiterbroadcasting.com/lup" podcast linux)                                    ; LINUX Unplugged
          ("https://feeds.fireside.fm/selfhosted/rss" podcast linux)                                     ; Self-Hosted
          ("https://feeds.redcircle.com/f8fe71b6-911e-4abb-8fdc-cebda631a2da" podcast homeassistant)     ; Home Assistant

          ;; Podcasts - Science / Interviews
          ("https://feeds.megaphone.fm/hubermanlab" podcast science)                                     ; Huberman Lab
          ("https://lexfridman.com/feed/podcast/" podcast interviews)                                    ; Lex Fridman
          ("https://rss2.flightcast.com/xmsftuzjjykcmqwolaqn6mdn" podcast interviews)                    ; Diary of a CEO

          ;; Podcasts - Electronics
          ("https://theamphour.com/feed/podcast/" podcast electronics)                                   ; The Amp Hour

          ;; Podcasts - Other
          ("https://evilgeniuschronicles.org/feed.xml" podcast)))                                        ; Evil Genius Chronicles

  ;; Show entries from the last 2 weeks by default
  (setq elfeed-search-filter "@2-weeks-ago +unread")

  ;; Download directory for podcast enclosures
  (setq elfeed-enclosure-default-dir "~/gPodder/Downloads/")

  ;; Wider title column for podcast names
  (setq elfeed-search-title-max-width 80))

;; mpv IPC socket for playback control
(defvar my/mpv-socket (expand-file-name "mpv-socket" temporary-file-directory))
(defvar my/mpv-process nil)

(defun my/elfeed-play-enclosure-mpv ()
  "Play the first enclosure of the current elfeed entry with mpv."
  (interactive)
  (my/mpv-stop)
  (let* ((entry (if (eq major-mode 'elfeed-show-mode)
                    elfeed-show-entry
                  (elfeed-search-selected :single)))
         (enclosures (elfeed-entry-enclosures entry)))
    (if enclosures
        (progn
          (setq my/mpv-process
                (start-process "mpv" nil "mpv" "--no-video"
                               (format "--input-ipc-server=%s" my/mpv-socket)
                               (caar enclosures)))
          (message "Playing: %s" (elfeed-entry-title entry)))
      (message "No enclosures found for this entry."))))

(defun my/mpv-send (command)
  "Send a JSON COMMAND to the running mpv instance."
  (when (file-exists-p my/mpv-socket)
    (start-process "mpv-cmd" nil "socat" "-"
                   (format "UNIX-CONNECT:%s" my/mpv-socket)
                   :input (format "%s\n" (json-encode `((command . ,command)))))))

(defun my/mpv-send-via-shell (command)
  "Send a JSON COMMAND string to mpv via shell."
  (when (file-exists-p my/mpv-socket)
    (call-process-shell-command
     (format "echo '%s' | socat - UNIX-CONNECT:%s"
             (json-encode `((command . ,command)))
             my/mpv-socket)
     nil nil nil)))

(defun my/mpv-pause-toggle ()
  "Toggle pause/play on the current mpv podcast."
  (interactive)
  (my/mpv-send-via-shell '("cycle" "pause"))
  (message "mpv: toggled pause"))

(defun my/mpv-seek-forward ()
  "Seek forward 30 seconds."
  (interactive)
  (my/mpv-send-via-shell '("seek" "30"))
  (message "mpv: +30s"))

(defun my/mpv-seek-backward ()
  "Seek backward 10 seconds."
  (interactive)
  (my/mpv-send-via-shell '("seek" "-10"))
  (message "mpv: -10s"))

(defun my/mpv-stop ()
  "Stop mpv playback."
  (interactive)
  (when (and my/mpv-process (process-live-p my/mpv-process))
    (kill-process my/mpv-process))
  (setq my/mpv-process nil)
  (when (file-exists-p my/mpv-socket)
    (delete-file my/mpv-socket)))

(defun my/elfeed--sanitize (name)
  "Strip NAME down to something safe for a filename."
  (replace-regexp-in-string "[^a-zA-Z0-9 _-]" "" name))

(defun my/elfeed-download-enclosure ()
  "Download the first enclosure of the current elfeed entry.
Ordinary files go to wget, which can resume.  An HLS playlist has no
single file to fetch, so those go to ffmpeg instead, which stitches the
segments and copies the AAC through without re-encoding.  Triple R serves
the rrr-feed podcasts that way."
  (interactive)
  (let* ((entry (if (eq major-mode 'elfeed-show-mode)
                    elfeed-show-entry
                  (elfeed-search-selected :single)))
         (enclosures (elfeed-entry-enclosures entry)))
    (if (not enclosures)
        (message "No enclosures found.")
      (let* ((url (caar enclosures))
             (feed (elfeed-entry-feed entry))
             (dir (expand-file-name
                   (my/elfeed--sanitize (elfeed-feed-title feed))
                   elfeed-enclosure-default-dir))
             (hls (string-match-p "\\.m3u8\\(\\?\\|$\\)" url)))
        (unless (file-directory-p dir)
          (make-directory dir t))
        (let ((default-directory dir))
          (if hls
              (let ((out (concat (my/elfeed--sanitize
                                  (or (elfeed-entry-title entry) "episode"))
                                 ".m4a")))
                (if (file-exists-p (expand-file-name out dir))
                    (message "Already downloaded: %s" out)
                  (start-process "ffmpeg" "*elfeed-download*" "ffmpeg"
                                 "-nostdin" "-loglevel" "warning"
                                 "-i" url "-c" "copy" "-bsf:a" "aac_adtstoasc"
                                 out)
                  (message "Downloading (HLS) to %s/%s" dir out)))
            (start-process "wget" "*elfeed-download*" "wget" "-c" url)
            (message "Downloading to %s" dir)))))))

(with-eval-after-load 'elfeed-search
  (define-key elfeed-search-mode-map (kbd "P") #'my/elfeed-play-enclosure-mpv)
  (define-key elfeed-search-mode-map (kbd "D") #'my/elfeed-download-enclosure)
  (define-key elfeed-search-mode-map (kbd "p") #'my/mpv-pause-toggle)
  (define-key elfeed-search-mode-map (kbd "F") #'my/mpv-seek-forward)
  (define-key elfeed-search-mode-map (kbd "B") #'my/mpv-seek-backward)
  (define-key elfeed-search-mode-map (kbd "S") #'my/mpv-stop)
  (define-key elfeed-search-mode-map (kbd "<XF86AudioPlay>") #'my/mpv-pause-toggle)
  (define-key elfeed-search-mode-map (kbd "<XF86AudioStop>") #'my/mpv-stop))

(with-eval-after-load 'elfeed-show
  (define-key elfeed-show-mode-map (kbd "P") #'my/elfeed-play-enclosure-mpv)
  (define-key elfeed-show-mode-map (kbd "D") #'my/elfeed-download-enclosure)
  (define-key elfeed-show-mode-map (kbd "p") #'my/mpv-pause-toggle)
  (define-key elfeed-show-mode-map (kbd "F") #'my/mpv-seek-forward)
  (define-key elfeed-show-mode-map (kbd "B") #'my/mpv-seek-backward)
  (define-key elfeed-show-mode-map (kbd "S") #'my/mpv-stop)
  (define-key elfeed-show-mode-map (kbd "<XF86AudioPlay>") #'my/mpv-pause-toggle)
  (define-key elfeed-show-mode-map (kbd "<XF86AudioStop>") #'my/mpv-stop))

;; Global multimedia key bindings for mpv control
(global-set-key (kbd "<XF86AudioPlay>") #'my/mpv-pause-toggle)
(global-set-key (kbd "<XF86AudioStop>") #'my/mpv-stop)

;;; 38-elfeed.el ends here
