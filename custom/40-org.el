;;; -*- lexical-binding: t; -*-
(use-package org-attach-screenshot :ensure t :defer 5)

;; Enable ODT export backend
(with-eval-after-load 'org
  (require 'ox-odt)
  (setq org-odt-preferred-output-format "odt"))

;; Hide major/minor modes and git branch in org-mode
(defun my/org-mode-line-minimal ()
  "Simplify mode-line in org-mode buffers."
  (setq-local mode-line-format
              (list "%e"
                    '(:eval (if (buffer-modified-p) " ● " "   "))
                    " %b"
                    " %l:%c"
                    '(:eval (when (org-clocking-p)
                              (concat "  " (org-clock-get-clock-string))))
                    " %-")))
(add-hook 'org-mode-hook #'my/org-mode-line-minimal)

;; Org mode shortcuts
(global-set-key (kbd "C-c C-x C-v") 'do-org-show-all-inline-images)
(global-set-key (kbd "C-c C-x C-r") 'org-clock-report)
(global-set-key "\C-cl" 'org-store-link)
(global-set-key "\C-ca" 'org-agenda)
(global-set-key (kbd "s-h") 'puborg)
(global-set-key (kbd "s-i") 'org-clock-in)
(global-set-key (kbd "s-o") 'org-clock-out)

;; F12 toggles the clock from point: clock out when point is already in the
;; clocked task, otherwise clock into the task at point.
;; (F9 is not usable here - Hyprland binds it to voxtype push-to-talk.)
(defun my/org-clocked-heading ()
  "Return the heading being clocked, as a cons of (BUFFER . POSITION).
Return nil when no clock is running."
  (when (and (org-clocking-p) (buffer-live-p (marker-buffer org-clock-marker)))
    (with-current-buffer (marker-buffer org-clock-marker)
      (save-excursion
        (goto-char org-clock-marker)
        (org-back-to-heading t)
        (cons (current-buffer) (point))))))

(defun my/org-clocked-marker-p (marker)
  "Return non-nil when MARKER sits in the entry that is clocked in."
  (let ((clocked (my/org-clocked-heading)))
    (when (and clocked marker (marker-buffer marker)
               (eq (marker-buffer marker) (car clocked)))
      (let ((pos (with-current-buffer (marker-buffer marker)
                   (save-excursion
                     (goto-char marker)
                     (unless (org-before-first-heading-p)
                       (org-back-to-heading t)
                       (point))))))
        (and pos (= pos (cdr clocked)))))))

(defun my/org-clock-toggle ()
  "Toggle the org clock from point.
Clock out when point is in the task that is already clocked in.  On
any other task, clock into that task instead.  Outside a heading,
clock out if a clock is running."
  (interactive)
  (cond
   ((derived-mode-p 'org-agenda-mode)
    (let ((marker (or (org-get-at-bol 'org-hd-marker)
                      (org-get-at-bol 'org-marker))))
      (cond ((my/org-clocked-marker-p marker) (org-agenda-clock-out))
            (marker (org-agenda-clock-in))
            ((org-clocking-p) (org-agenda-clock-out))
            (t (message "No org task on this line")))))
   ((derived-mode-p 'org-mode)
    (cond ((my/org-clocked-marker-p (point-marker)) (org-clock-out))
          ((org-before-first-heading-p)
           (if (org-clocking-p)
               (org-clock-out)
             (message "Point is not in an org task")))
          (t (org-clock-in))))
   ((org-clocking-p) (org-clock-out))
   (t (message "No clock running and no org task at point"))))

(global-set-key [f12] 'my/org-clock-toggle)

;; Org-babel languages
(org-babel-do-load-languages
 'org-babel-load-languages
 '((emacs-lisp . t)
   (python . t)
   (shell . t)
   (ruby . t)
   (js . t)))

;; Org-mode options
(add-hook 'org-mode-hook 'turn-on-visual-line-mode)
(setq org-clock-out-remove-zero-time-clocks t)
(setq org-duration-format (quote h:mm))
(setq org-directory "~/org")
(setq org-agenda-files '("~/org/" "~/org/business/michael" "~/org/projects"))
;; Format the time in clock tables.
(setq org-time-clocksum-format (quote (:hours "%d" :require-hours t :minutes ":%02d" :require-minutes t)))

(setq org-list-allow-alphabetical t)

;; Display inline images
(defun do-org-show-all-inline-images ()
  (interactive)
  (org-display-inline-images t t))

;; Assign mode to .org files
(add-to-list 'auto-mode-alist '("\\.org$" . org-mode))
(add-hook 'org-mode-hook (lambda () (display-line-numbers-mode 0)))

;; Set more workflow states than TODO
(setq org-todo-keywords
	  '((sequence "TODO(t)" "|" "DONE(d)" "REDUNDANT(r)" )
		  (sequence "DELEGATED(<)" "|" "DONE(d)")
		  (sequence "GONNA(g)" "|" "DONE(d)" )
      (sequence "HOBBY(h)" "|" "DONE(d)" )
      ))

(setq org-support-shift-select t)


;; Put email links in org mode :) - currently broken :(
;; (setq ffap-url-regexp (replace-regexp-in-string "mailto:" "thunderlink: \ \ \ \ | mailto:" ffap-url-regexp));; for ThunderLink

;;  (defun browse-url-thunderlink (url & optional new-window)
;;    (interactive (browse-url-interactive-arg "URL:"))
;;    (if (string-match "^ thunderlink ://" url)
;;        (progn
;;          (start-process (concat "thunderbird" url) nil "thunderbird" "-thunderlink" url)
;;          t)
;;      nil)
;;    )
;; (unless (listp browse-url-browser-function) (setq browse-url-browser-function (list (cons "." browse-url-browser-function))))
;; (add-to-list 'browse-url-browser-function' ("^ thunderlink:". browse-url-thunderlink))

;; (add-hook 'org-load-hook
;;             '(lambda ()
;;                (add-to-list 'org-link-types "thunderlink")
;;                (org-make-link-regexps)
;;                (add-hook 'org-open-link-functions' browse-url-thunderlink)
;;                ))

;; Set archive location
(setq org-archive-location "~/org/archive/%s_archive::")

;; Custom searches
(setq org-agenda-custom-commands
      '(("Q" . "Custom queries") ;; gives label to "Q"
        ("Qa" "Archive search" search ""
         ((org-agenda-files (file-expand-wildcards "~/org/archive/*.org_archive"))))
        ;; ("Qw" "Website search" search ""
        ;;  ((org-agenda-files (file-expand-wildcards "~/website/*.org"))))
        ("Qb" "Projects and Archive" search ""
         ((org-agenda-text-search-extra-files (file-expand-wildcards "~/org/archive/*.org_archive"))))
        ;; searches both projects and org/archive directories
        ("QA" "Archive tags search" org-tags-view ""
         ((org-agenda-files (file-expand-wildcards "~/org/archive/*.org_archive"))))
        ;; ...other commands here
        ))

;; Display images inline automatically
(setq org-startup-with-inline-images t)

(defun org-clock-sum-agenda-today ()
  "Visit each file in `org-agenda-files' and return the total time of today's clocked tasks in minutes."
  (interactive)
  (let ((files (org-agenda-files))
        (total 0))
    (org-agenda-prepare-buffers files)
    (dolist (file files)
      (with-current-buffer (find-buffer-visiting file)
        (setq total (+ total (org-clock-sum-today)))))
    (message "Hours clocked for the day: %s" (/ total 60))))

;; Sorts the tables by time, largest to smallest
;;
;; example of clocktable line;
;; #+BEGIN: clocktable :maxlevel 1 :block today :scope agenda-with-archives :link t :stepskip0 t :fileskip0 t :formula % :formatter my-org-clocktable-sorter
(defun my-org-clocktable-sorter (ipos tables params)
  (setq tables (cl-sort tables (lambda (table1 table2) (> (nth 1 table1) (nth 1 table2)))))
  (funcall (or org-clock-clocktable-formatter 'org-clocktable-write-default) ipos tables params))

;; --- Wiki search -------------------------------------------------------------
;; index.org links to search.html, which never existed. Rather than a static
;; page (which cannot grep 748 files) this is a route on the running server, so
;; results are always current and there is no index to rebuild.

(defvar org-ehtml-search-max-files 100
  "Maximum number of files listed in one search result page.")

(defvar org-ehtml-search-max-hits 5
  "Maximum matching lines shown per file.")

(defun org-ehtml-search--escape (s)
  "HTML-escape S."
  (let ((s (or s "")))
    (dolist (pair '(("&" . "&amp;") ("<" . "&lt;") (">" . "&gt;") ("\"" . "&quot;")) s)
      (setq s (replace-regexp-in-string (car pair) (cdr pair) s t t)))))

(defun org-ehtml-search--highlight (line query)
  "HTML-escape LINE and wrap case-insensitive occurrences of QUERY in <mark>."
  (let ((case-fold-search t)
        (esc (org-ehtml-search--escape line))
        (q   (org-ehtml-search--escape query)))
    (if (string-empty-p q)
        esc
      (replace-regexp-in-string (regexp-quote q)
                                (lambda (m) (concat "<mark>" m "</mark>"))
                                esc t t))))

(defun org-ehtml-search--run (query)
  "Return an alist of (RELATIVE-PATH . ((LINE-NO . TEXT) ...)) matching QUERY.
Matching is literal and case-insensitive, so a phrase or a partial word works."
  (let ((default-directory org-ehtml-docroot)
        results)
    (with-temp-buffer
      ;; -F literal, -i case-insensitive, -I skip binaries, -m cap per file.
      (call-process "grep" nil t nil
                    "-rnI" "-i" "-F"
                    (format "-m%d" org-ehtml-search-max-hits)
                    "--include=*.org" "--include=*.html"
                    "--exclude-dir=.git"
                    "--" query ".")
      (goto-char (point-min))
      (while (re-search-forward "^\\./\\([^\0:]+\\):\\([0-9]+\\):\\(.*\\)$" nil t)
        (let* ((file (match-string 1))
               (line (string-to-number (match-string 2)))
               (text (string-trim (match-string 3)))
               (cell (assoc file results)))
          (if cell
              (setcdr cell (cons (cons line text) (cdr cell)))
            (push (cons file (list (cons line text))) results)))))
    ;; org-ehtml caches each exported page as a .html sibling of its .org, so
    ;; a hit in foo.org usually also hits foo.html and the same page would be
    ;; listed twice - and the .html copy matches export markup as well as
    ;; prose. Drop any .html that has a .org beside it; the .org is the source
    ;; and is what the server renders. Standalone .html files are kept.
    (setq results
          (seq-remove (lambda (c)
                        (let ((f (car c)))
                          (and (string-suffix-p ".html" f)
                               (file-exists-p
                                (expand-file-name
                                 (concat (file-name-sans-extension f) ".org")
                                 org-ehtml-docroot)))))
                      results))
    (mapcar (lambda (c) (cons (car c) (nreverse (cdr c))))
            (nreverse results))))

(defun org-ehtml-search--text-fragment (s)
  "Percent-encode S for use in a #:~:text= URL fragment.
`url-hexify-string' leaves - alone because it is unreserved, but - is
separator syntax inside a text fragment, so encode it too."
  (replace-regexp-in-string "-" "%2D" (url-hexify-string (string-trim s)) t t))

(defun org-ehtml-search--page (query)
  "Return the full HTML page for QUERY (nil or empty shows just the form)."
  (let* ((q (or query ""))
         (results (unless (string-empty-p (string-trim q))
                    (org-ehtml-search--run (string-trim q))))
         (shown (seq-take results org-ehtml-search-max-files)))
    (concat
     "<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\"/>"
     "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"/>"
     "<title>Search</title>"
     "<link rel=\"stylesheet\" type=\"text/css\" href=\"css/stylesheet.css\"/>"
     "<style>"
     "body{font-family:system-ui,sans-serif;max-width:60em;margin:2em auto;padding:0 1em;line-height:1.5}"
     "form{display:flex;gap:.5em;margin-bottom:1.5em}"
     "input[type=search]{flex:1;padding:.5em;font-size:1rem}"
     "button{padding:.5em 1.2em;font-size:1rem;cursor:pointer}"
     "li{margin-bottom:1.2em;list-style:none}"
     "ul{padding-left:0}"
     ".hit{font-family:ui-monospace,monospace;font-size:.85rem;color:#555;margin:.15em 0 .15em 1.5em;"
     "white-space:pre-wrap;word-break:break-word}"
     ".ln{color:#999;margin-right:.6em}"
     "mark{background:#ffe066;padding:0 .1em}"
     ".count{color:#666;margin-bottom:1em}"
     "</style></head><body>"
     "<h1>Search the manual</h1>"
     "<form action=\"/search\" method=\"get\">"
     "<input type=\"search\" name=\"q\" autofocus placeholder=\"phrase or partial word\" value=\""
     (org-ehtml-search--escape q) "\"/>"
     "<button type=\"submit\">Search</button></form>"
     "<p><a href=\"/index.org\">&larr; Back to index</a></p>"
     (cond
      ((string-empty-p (string-trim q)) "")
      ((null results)
       (concat "<p class=\"count\">No matches for <strong>"
               (org-ehtml-search--escape q) "</strong>.</p>"))
      (t
       (concat
        "<p class=\"count\">" (number-to-string (length results))
        (if (= 1 (length results)) " file matches " " files match ")
        "<strong>" (org-ehtml-search--escape q) "</strong>"
        (if (> (length results) org-ehtml-search-max-files)
            (format " (showing the first %d)" org-ehtml-search-max-files) "")
        ".</p><ul>"
        (mapconcat
         (lambda (entry)
           (let* ((file (car entry)) (hits (cdr entry))
                  (frag (org-ehtml-search--text-fragment (string-trim q))))
             ;; Hexify per segment: url-hexify-string's second argument is a
             ;; list of allowed characters, not a string, and "/" must survive.
             (concat "<li><a href=\"/"
                     (mapconcat #'url-hexify-string (split-string file "/") "/")
                     ;; Scroll the page to the first occurrence rather than
                     ;; landing at the top. Needs a browser with
                     ;; scroll-to-text-fragment; elsewhere it is ignored and
                     ;; the page simply opens at the top.
                     "#:~:text=" frag "\">"
                     (org-ehtml-search--escape file) "</a>"
                     (mapconcat
                      (lambda (hit)
                        (concat "<div class=\"hit\"><span class=\"ln\">"
                                (number-to-string (car hit)) "</span>"
                                (org-ehtml-search--highlight (cdr hit) (string-trim q))
                                "</div>"))
                      hits "")
                     "</li>")))
         shown "")
        "</ul>")))
     "</body></html>")))

(defun org-ehtml-search-handler (request)
  "Serve the search form, and results when a q parameter is present."
  (with-slots (process headers) request
    (let ((body (org-ehtml-search--page (cdr (assoc "q" headers)))))
      (ws-response-header process 200 '("Content-type" . "text/html; charset=utf-8"))
      (process-send-string process body))))

;; WIKI
(use-package web-server :ensure t)
(use-package org-ehtml
  :load-path "external/org-ehtml/src"
  :config
  (setq org-ehtml-docroot (expand-file-name "~/org/business"))
  (setq org-ehtml-everything-editable t)
  ;; Route /search and /search.html to the search page. Must be prepended
  ;; before ws-start: ws-start captures the handler list by value, and the
  ;; catch-all ((:GET . ".*")) below would otherwise match first.
  (add-to-list 'org-ehtml-handler
               '((:GET . "^/search\\(\\.html\\)?$") . org-ehtml-search-handler))
  (ws-start org-ehtml-handler 8888 nil :host "0.0.0.0"))



;;  Currently broken on second commit.
;; ;; Autocommit changes made through org-ehtml
;; (require 'vc)
;; (defun commit-ehtml-edit (request)
;;   (let ((file (buffer-file-name (current-buffer))))
;;     (vc-checkin (list file)
;;                 (vc-backend file) "edit through org-ehtml")))

;; (add-hook 'org-ehtml-after-save-hook 'commit-ehtml-edit)

(load "count-todo")
(load "async-agenda")

;; plotting
(global-set-key "\M-\C-g" 'org-plot/gnuplot)

;; set time
(setq org-clock-display-default-range 'untilnow)

;; I take screenshots all the time
(global-set-key (kbd "s-s") 'org-attach-screenshot)


;; Display list of TODO items in CREATED order
(defun my/org-list-todos-by-created ()
  "List only 'TODO' items from .org files under ~/org/business/michael as an Org table.
Includes :CREATED: property if present and sorts the table by it."
  (interactive)
  (let* ((target-dir (expand-file-name "~/org/business/michael"))
         (org-files (when (file-directory-p target-dir)
                      (directory-files-recursively target-dir "\\.org$")))
         ;; Header + separator
         (todo-rows '(("File" "Headline" "Created")
                      ("--------" "--------" "--------"))))
    ;; Collect TODOs with :CREATED:
    (dolist (file org-files)
      (with-current-buffer (find-file-noselect file)
        (org-with-wide-buffer
         (org-element-map (org-element-parse-buffer) 'headline
           (lambda (hl)
             (let* ((todo (org-element-property :todo-keyword hl)))
               (when (and todo (string= todo "TODO"))
                 (save-excursion
                   (goto-char (org-element-property :begin hl))
                   (let* ((props (org-entry-properties))
                          (created (or (cdr (assoc "CREATED" props)) "")) ;; raw value
                          (title (org-element-property :raw-value hl)))
                     (push (list (file-name-nondirectory file)
                                 title
                                 (org-trim created))
                           todo-rows))))))))))
    ;; Sort rows by CREATED
    (let ((data-rows (cl-subseq (nreverse todo-rows) 2))) ;; skip header+sep
      (setq data-rows
            (sort data-rows
                  (lambda (a b)
                    (let ((da (car (split-string (nth 2 a)))) ; extract YYYY-MM-DD
                          (db (car (split-string (nth 2 b)))))
                      (cond
                       ((and (string-empty-p da) (not (string-empty-p db))) t)
                       ((and (not (string-empty-p da)) (string-empty-p db)) nil)
                       (t (string< da db)))))))
      ;; Prepend header
      (setq todo-rows (append '(("File" "Headline" "Created")
                                ("--------" "--------" "--------"))
                              data-rows)))
    ;; Output buffer
    (with-current-buffer (get-buffer-create "*TODO Items*")
      (erase-buffer)
      (insert (format "* TODO items from %s (%d files)\n\n"
                      target-dir (length org-files)))
      (dolist (row todo-rows)
        (insert (format "| %s | %s | %s |\n"
                        (nth 0 row) (nth 1 row) (nth 2 row))))
      (goto-char (point-min))
      (org-mode)
      (org-table-align)
      (display-buffer (current-buffer)))))

;; Paste an image from the clipboard into the org file at point.
;;
;; Most of this already ships with Org 9.8: org-mode registers a `yank-media'
;; handler for "image/.*", and `org-yank-image-save-method' defaults to
;; `attach', so a pasted image is written into the entry's org-attach store
;; (data/<id>/) and an attachment: link is inserted at point. What was
;; missing is a key bound to `yank-media', plus the two fixes below.
;;
;; Flow: SUPER+V picks the image out of the omarchy clipboard history, then
;; C-y in the org buffer attaches it and shows it inline.
;;
;; C-y stays correct for ordinary text: `yank-media' signals a user-error
;; when nothing on the clipboard matches a handler, and we fall back to
;; `org-yank'. Besides images, org's handlers also cover LibreOffice cells
;; and files copied from a file manager, so those get attached too.

(defun my/org-undescribe-image-links (beg end)
  "Strip the description from image links between BEG and END.
`org-link-preview-region' only previews a link that has no description,
but `org--image-yank-media-handler' inserts the filename as one, giving
[[attachment:foo.png][foo.png]].  Dropping the redundant description is
what makes the image render - both right after pasting and on reopening
the file, since `org-startup-with-link-previews' is on."
  (require 'image-file)
  (save-excursion
    (goto-char beg)
    (while (re-search-forward org-link-bracket-re end t)
      (let ((path (match-string-no-properties 1))
            (desc (match-string-no-properties 2)))
        (when (and desc
                   (string-match-p "\\`\\(?:attachment\\|file\\):" path)
                   (member (downcase (or (file-name-extension path) ""))
                           image-file-name-extensions))
          (replace-match (org-link-make-string path) t t))))))

(defun my/org-yank-media-or-yank (&optional arg)
  "Paste clipboard media at point, falling back to `org-yank'.
An image is saved into this entry's org-attach directory, linked with an
attachment: link, and previewed inline.  ARG is passed to `org-yank'."
  (interactive "P")
  (let ((beg (copy-marker (point) nil))
        (end (copy-marker (point) t)))
    (unwind-protect
        (if (condition-case nil
                (progn (yank-media) t)
              (user-error nil))
            (progn
              (my/org-undescribe-image-links beg end)
              (when (display-graphic-p)
                (org-link-preview-region nil t beg end)))
          (org-yank arg))
      (set-marker beg nil)
      (set-marker end nil))))

(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-y") #'my/org-yank-media-or-yank)
  ;; Unconditional media paste, for when C-y guessed wrong.
  ;; (C-c C-y and C-c y are already taken by org-evaluate-time-range and
  ;; youtube-music; s-v never reaches Emacs because Hyprland grabs SUPER+V.)
  (define-key org-mode-map (kbd "C-c C-M-y") #'yank-media))

;; Inline images are capped at `fill-column' wide, which shrinks most pasted
;; screenshots. Show them 50% wider than that.
;;
;; `org-image-max-width' only understands the symbol `fill-column' or a pixel
;; count, so the column target has to be converted using the frame's char
;; width. It must be a *graphical* frame: the daemon's own terminal frame
;; reports a char width of 1, so using the selected frame would cap images at
;; ~105px whenever a file is opened with no GUI frame selected (during an
;; agenda scan, say). When no graphical frame exists we leave the default
;; alone rather than guess.
;;
;; This only takes effect because `org-image-actual-width' is t; a #+ATTR_ORG
;; :width on an individual image still wins.
(defconst my/org-image-width-scale 1.5
  "Inline image width cap, as a multiple of `fill-column'.")

(defun my/org-image-max-width ()
  "Pixel width cap for inline images, or nil with no graphical frame."
  (when-let* ((frame (seq-find #'display-graphic-p (frame-list))))
    (round (* my/org-image-width-scale fill-column (frame-char-width frame)))))

(defun my/org-set-image-max-width ()
  "Widen this buffer's inline image cap to `my/org-image-width-scale'."
  (when-let* ((px (my/org-image-max-width)))
    (setq-local org-image-max-width px)))

(add-hook 'org-mode-hook #'my/org-set-image-max-width)
