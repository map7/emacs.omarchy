;;; 38-elfeed.el --- Elfeed podcast/feed reader configuration  -*- lexical-binding: t; -*-

;;; Code:

(use-package elfeed
  :bind ("C-x w" . elfeed)
  :config
  (setq elfeed-feeds
        `(;; Podcasts - Accounting
          ("https://rss.buzzsprout.com/1761225.rss" podcast accounting)                                  ; Aly & Andrews All Aussie Accounting Adventures

          ;; Podcasts - Finance
          ("https://www.omnycontent.com/d/playlist/fa326977-3de5-4283-9b8b-af3500c58607/0c6189e6-78f6-4f47-b25d-af4600179991/1dc0ac03-61e1-486c-b9be-af460017999b/podcast.rss" podcast finance) ; She's On The Money

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
          ("https://evilgeniuschronicles.org/feed.xml" podcast)                                          ; Evil Genius Chronicles
          ))

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

;; Adding and removing feeds
;;
;; `elfeed-feeds' above is edited as text, so its sections and comments
;; survive.  Each feed is one line, ("URL" tags...) then "; Title", under
;; a ";; Podcasts - Section" heading.  Feeds written any other way (such
;; as the file:// one) still work but are left alone here.

(defvar my/elfeed-config-file (or load-file-name buffer-file-name)
  "This file, which holds `elfeed-feeds'.")

(defconst my/elfeed-feed-line-re
  "^[ \t]*(\"\\([^\"]+\\)\"\\([^)]*\\))[ \t]*\\(?:;+[ \t]*\\(.*\\)\\)?$"
  "A one-line feed: group 1 is the URL, 2 the tags, 3 the title.")

(defconst my/elfeed-section-re "^[ \t`(]*;; Podcasts - \\(.+\\)$"
  "A section heading: group 1 is the section name.")

(defun my/elfeed--feeds-bounds ()
  "Return (BEG . END) of the `elfeed-feeds' form in the current buffer."
  (goto-char (point-min))
  (re-search-forward "(setq elfeed-feeds")
  (let ((beg (point)))
    (goto-char (match-beginning 0))
    (forward-sexp)
    (cons beg (point))))

(defun my/elfeed--sections ()
  "Return the section headings as (NAME . POS), POS at the heading line."
  (let ((bounds (my/elfeed--feeds-bounds))
        sections)
    (goto-char (car bounds))
    (while (re-search-forward my/elfeed-section-re (cdr bounds) t)
      (push (cons (match-string-no-properties 1) (line-beginning-position))
            sections))
    (nreverse sections)))

(defun my/elfeed--section-end (pos)
  "Return the start of the line after the section whose heading is at POS.
A section runs until a blank line or the list's closing parens."
  (goto-char pos)
  (forward-line 1)
  (while (not (looking-at-p "^[ \t]*\\()\\|$\\)"))
    (forward-line 1))
  (point))

(defun my/elfeed--section-tags (pos)
  "Return the tags of the first feed in the section at POS, or nil."
  (let ((end (my/elfeed--section-end pos)))
    (goto-char pos)
    (when (re-search-forward my/elfeed-feed-line-re end t)
      (string-trim (match-string-no-properties 2)))))

(defun my/elfeed--feed-lines ()
  "Return the one-line feeds as (LABEL URL . POS)."
  (let ((bounds (my/elfeed--feeds-bounds))
        section feeds)
    (goto-char (car bounds))
    (while (< (point) (cdr bounds))
      (cond ((looking-at my/elfeed-section-re)
             (setq section (match-string-no-properties 1)))
            ((looking-at my/elfeed-feed-line-re)
             (let ((url (match-string-no-properties 1))
                   (title (match-string-no-properties 3)))
               (push (cons (format "%-24s %s" section (or title url))
                           (cons url (point)))
                     feeds))))
      (forward-line 1))
    (nreverse feeds)))

(defun my/elfeed--fetch-title (url)
  "Fetch the feed at URL and return its title, or nil if that fails."
  (ignore-errors
    (let ((buf (url-retrieve-synchronously url t t 30)))
      (with-current-buffer buf
        (unwind-protect
            (progn
              (goto-char (or (bound-and-true-p url-http-end-of-headers)
                             (point-min)))
              (set-buffer-multibyte t)
              (decode-coding-region (point) (point-max) 'utf-8)
              ;; libxml gives up on anything before the <?xml declaration.
              (skip-chars-forward " \t\r\n")
              (let ((title (car (dom-by-tag
                                 (libxml-parse-xml-region (point) (point-max))
                                 'title))))
                (when title
                  (string-trim (dom-texts title "")))))
          (kill-buffer buf))))))

(defun my/elfeed--clipboard-url ()
  "Return the latest kill if it looks like a URL, else nil."
  (let ((kill (ignore-errors (string-trim (current-kill 0 t)))))
    (when (and kill (string-match-p "\\`\\(https?\\|file\\)://[^ \n]+\\'" kill))
      kill)))

(defun my/elfeed--config-buffer ()
  "Return a buffer visiting `my/elfeed-config-file', refusing unsaved edits."
  (let ((buf (find-file-noselect my/elfeed-config-file)))
    (when (buffer-modified-p buf)
      (user-error "Save or revert %s first" (buffer-name buf)))
    buf))

(defun my/elfeed--reload ()
  "Reload `elfeed-feeds' from this file, fetch every feed, redraw the list."
  (load my/elfeed-config-file nil t)
  (elfeed-update)
  (when-let ((buf (get-buffer "*elfeed-search*")))
    (with-current-buffer buf
      (elfeed-search-update :force))))

(defun elfeed-add (url)
  "Subscribe to the feed at URL.
Fetches the feed's title, asks which section it belongs in (a new name
makes a new section) and which tags to give it, writes it into this
file, then reloads and fetches."
  (interactive
   (list (string-trim (read-string "Feed URL: " (my/elfeed--clipboard-url)))))
  (require 'elfeed)
  (when (seq-find (lambda (f) (equal (if (consp f) (car f) f) url))
                  elfeed-feeds)
    (user-error "Already subscribed to %s" url))
  (message "Fetching %s..." url)
  (let ((title (read-string "Title: " (my/elfeed--fetch-title url))))
    (when (string-empty-p title)
      (setq title url))
    (with-current-buffer (my/elfeed--config-buffer)
      (save-excursion
        (let* ((sections (my/elfeed--sections))
               (name (completing-read "Section: " sections))
               (pos (cdr (assoc name sections)))
               (tags (read-string "Tags: "
                                  (if pos
                                      (my/elfeed--section-tags pos)
                                    (concat "podcast " (downcase name))))))
          (if pos
              (goto-char (my/elfeed--section-end pos))
            ;; A new section goes last, just above the closing parens.
            (goto-char (cdr (my/elfeed--feeds-bounds)))
            (beginning-of-line)
            (insert "\n          ;; Podcasts - " name "\n"))
          (insert (format "          (%S %s)" url tags))
          (indent-to 105 1)
          (insert "; " title "\n")))
      (save-buffer))
    (my/elfeed--reload)
    (message "Added %s" title)))

(defun elfeed-remove ()
  "Pick a feed from a list and unsubscribe from it.
Deletes its line from this file (and its section heading, if that was
the last feed in it), marks its entries read so they leave the default
unread listing, then reloads."
  (interactive)
  (require 'elfeed)
  (let (url label)
    (with-current-buffer (my/elfeed--config-buffer)
      (save-excursion
        (let* ((feeds (my/elfeed--feed-lines))
               (choice (completing-read "Remove feed: " feeds nil t))
               (feed (cdr (assoc choice feeds))))
          (unless (y-or-n-p (format "Remove %s? " (string-trim choice)))
            (user-error "Cancelled"))
          (setq url (car feed)
                label (string-trim choice))
          (goto-char (cdr feed))
          (delete-region (line-beginning-position) (line-beginning-position 2))
          ;; Drop the heading (and the blank line before it) if the
          ;; section is now empty.
          (when (and (looking-at-p "^[ \t]*\\()\\|$\\)")
                     (save-excursion
                       (forward-line -1)
                       (looking-at-p "^[ \t]*;; Podcasts - ")))
            (forward-line -1)
            (delete-region (point) (line-beginning-position 2))
            (when (save-excursion
                    (forward-line -1)
                    (looking-at-p "^[ \t]*$"))
              (forward-line -1)
              (delete-region (point) (line-beginning-position 2)))))
        (save-buffer)))
    (with-elfeed-db-visit (entry _feed)
      (when (equal (elfeed-entry-feed-id entry) url)
        (elfeed-untag entry 'unread)))
    (my/elfeed--reload)
    (message "Removed %s" label)))

(with-eval-after-load 'elfeed-search
  (define-key elfeed-search-mode-map (kbd "A") #'elfeed-add)
  (define-key elfeed-search-mode-map (kbd "R") #'elfeed-remove)
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
