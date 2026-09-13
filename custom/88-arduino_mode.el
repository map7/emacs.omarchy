;; arduino-mode with arduino-cli  -*- lexical-binding: t; -*-
;;
;; C-c a c  = compile
;; C-c a u  = upload (USB serial)
;; C-c a t  = upload over TCP (OTA)
;; C-c a s  = set TCP host (manual)
;; C-c a d  = discover and pick TCP host via mDNS
;; C-c a m  = open serial monitor
;;
;; Sketches that set `arduino-build-owners' (per-project, in .dir-locals.el)
;; also get prompted for an owner on each compile/upload.

(defvar arduino-board "esp32:esp32:esp32c3"
  "FQBN for arduino-cli (e.g. \"arduino:avr:uno\", \"esp32:esp32:esp32c3\").")

(defvar arduino-tcp-host nil
  "TCP host for OTA uploads (e.g. \"192.168.1.100\").
Left unset so this repo carries no LAN address.  `arduino-upload-tcp'
prompts when it is nil, and `arduino-pick-tcp-host' (C-c a d) finds
devices over mDNS.")

(defvar arduino-tcp-port "3232"
  "TCP port for OTA uploads.")

(defvar arduino-espota-script nil
  "Path to espota.py for ESP32 OTA uploads.
Nil autodetects the newest installed esp32 core, so the path does not go
stale when the core is upgraded.")

(defun arduino--espota-script ()
  "Return the path to espota.py, honouring `arduino-espota-script' when set."
  (or (and arduino-espota-script (expand-file-name arduino-espota-script))
      (car (last (sort (file-expand-wildcards
                        (expand-file-name
                         "~/.arduino15/packages/esp32/hardware/esp32/*/tools/espota.py"))
                       #'string-version-lessp)))
      (user-error "espota.py not found - set `arduino-espota-script'")))

(defvar arduino-serial-port "/dev/ttyACM0"
  "Serial port for USB uploads and monitoring.")

(defun arduino--sketch-dir ()
  "Find the sketch directory (directory containing the .ino file)."
  (or (locate-dominating-file default-directory
        (lambda (dir)
          (directory-files dir nil "\\.ino\\'" t)))
      default-directory))

(defun arduino--sketch-yaml-get (key)
  "Return the value of top-level KEY in the sketch's sketch.yaml, or nil.
Looks for sketch.yaml (or sketch.yml) in `arduino--sketch-dir'."
  (let* ((dir (arduino--sketch-dir))
         (file (seq-find #'file-readable-p
                         (list (expand-file-name "sketch.yaml" dir)
                               (expand-file-name "sketch.yml" dir)))))
    (when file
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (when (re-search-forward
               (format "^[ \t]*%s[ \t]*:[ \t]*\\(.*?\\)[ \t]*$" (regexp-quote key))
               nil t)
          (let ((val (string-trim (match-string 1) "[\"' \t]+" "[\"' \t]+")))
            (unless (string-empty-p val) val)))))))

(defun arduino--fqbn ()
  "Board FQBN for the current sketch.
Prefers `default_fqbn' from the sketch's sketch.yaml, falling back to
`arduino-board'."
  (or (arduino--sketch-yaml-get "default_fqbn") arduino-board))

(defun arduino--port ()
  "Serial port for the current sketch.
Prefers `default_port' from the sketch's sketch.yaml, falling back to
`arduino-serial-port'."
  (or (arduino--sketch-yaml-get "default_port") arduino-serial-port))

(defvar arduino-build-owners nil
  "Owner names to choose from when building this sketch, or nil for no prompt.
Set it per-project in .dir-locals.el, e.g.

    ((nil . ((arduino-build-owners . (\"michael\" \"adam\")))))

When non-nil, compiling prompts for one and passes it to arduino-cli as
-DOWNER=<name>.  The first entry is the initial default.")
(put 'arduino-build-owners 'safe-local-variable
     (lambda (v) (and (listp v) (seq-every-p #'stringp v))))

(defvar arduino-ota-host-format nil
  "Format string turning an owner into an OTA hostname, e.g. \"beer-%s.local\".
Set it per-project in .dir-locals.el alongside `arduino-build-owners'.  When
set, the owner chosen for the build also selects the device, so an OTA upload
cannot land one person's build on the other's board.")
(put 'arduino-ota-host-format 'safe-local-variable #'stringp)

(defvar-local arduino--owner nil
  "Owner last chosen in this buffer, used as the default next time.")

(defun arduino--read-owner ()
  "Prompt for a build owner, or return nil when this sketch declares none.
The choice is remembered as the default for the next build in this buffer."
  (when arduino-build-owners
    (let* ((default (or arduino--owner (car arduino-build-owners)))
           (owner (completing-read (format "Owner (default %s): " default)
                                   arduino-build-owners nil t nil nil default)))
      (setq arduino--owner owner))))

(defun arduino--owner-flag (owner)
  "Return the arduino-cli flag setting OWNER, or \"\" when OWNER is nil.
Sketches with no owners therefore build exactly the command they did before."
  (if owner
      (format " --build-property compiler.cpp.extra_flags=-DOWNER=%s" owner)
    ""))

(defun arduino--resolve-host (host)
  "Resolve HOST to an IPv4 address over mDNS, falling back to HOST itself."
  (if (not (and (string-suffix-p ".local" host)
                (executable-find "avahi-resolve-host-name")))
      host
    (let ((out (shell-command-to-string
                (format "avahi-resolve-host-name -4 %s 2>/dev/null"
                        (shell-quote-argument host)))))
      (if (string-match "^[^ \t]+[ \t]+\\([0-9.]+\\)" out)
          (match-string 1 out)
        (user-error "Cannot resolve %s - is the device powered on?" host)))))

(use-package arduino-mode
  :mode "\\.ino\\'"
  :config
  (defun arduino-set-tcp-host (host)
    "Set the TCP HOST for OTA uploads."
    (interactive "sArduino TCP host (e.g. 192.168.1.100): ")
    (setq arduino-tcp-host host)
    (message "Arduino TCP host set to %s:%s" host arduino-tcp-port))

  (defun arduino--discover-ota ()
    "Return alist of (\"name (ip)\" . ip) for ArduinoOTA devices on the LAN."
    (unless (executable-find "avahi-browse")
      (user-error "avahi-browse not found — install avahi-utils"))
    (let ((output (shell-command-to-string
                   "avahi-browse -rtp _arduino._tcp 2>/dev/null"))
          results)
      (dolist (line (split-string output "\n" t))
        ;; Resolved records start with "=" and are ';'-separated:
        ;; =;iface;proto;name;type;domain;hostname;address;port;txt
        (when (string-prefix-p "=" line)
          (let* ((fields (split-string line ";"))
                 (proto  (nth 2 fields))
                 (name   (nth 3 fields))
                 (addr   (nth 7 fields)))
            (when (and (string= proto "IPv4") name addr
                       (not (string-empty-p addr)))
              (push (cons (format "%s (%s)" name addr) addr) results)))))
      (nreverse results)))

  (defun arduino-pick-tcp-host ()
    "Discover ArduinoOTA devices via mDNS and set `arduino-tcp-host'."
    (interactive)
    (let ((devs (arduino--discover-ota)))
      (unless devs
        (user-error "No ArduinoOTA devices found via mDNS"))
      (let ((choice (completing-read "ESP device: " devs nil t)))
        (setq arduino-tcp-host (cdr (assoc choice devs)))
        (message "Arduino TCP host set to %s" arduino-tcp-host))))

  (defun arduino-compile ()
    "Compile the current Arduino sketch.
The board comes from `default_fqbn' in the sketch's sketch.yaml when present."
    (interactive)
    (let* ((owner (arduino--owner-flag (arduino--read-owner)))
           (default-directory (arduino--sketch-dir))
           (fqbn (arduino--fqbn)))
      (message "Arduino: compiling %s for %s" default-directory fqbn)
      (compile (format "arduino-cli compile -b %s%s ." fqbn owner))))

  (defun arduino-upload ()
    "Compile and upload to Arduino over USB serial.
The board and port come from `default_fqbn' and `default_port' in the
sketch's sketch.yaml when present."
    (interactive)
    (let* ((owner (arduino--owner-flag (arduino--read-owner)))
           (default-directory (arduino--sketch-dir))
           (fqbn (arduino--fqbn))
           (port (arduino--port))
           (sketch-name (file-name-nondirectory
                         (directory-file-name default-directory)))
           (build-dir "build"))
      (message "Arduino: uploading to %s for %s" port fqbn)
      ;; `upload' takes no --build-property, and the build cache is keyed on
      ;; the sketch path alone, so both owners share one directory.  Build to
      ;; a known place and upload that exact file.
      (compile (format "arduino-cli compile -b %s%s --output-dir %s . && arduino-cli upload -b %s -i %s/%s.ino.bin -p %s ."
                       fqbn owner build-dir fqbn build-dir sketch-name port))))

  (defun arduino-upload-tcp ()
    "Upload to Arduino over TCP (OTA) using espota.py.
When the sketch sets `arduino-ota-host-format', the owner chosen for the
build also picks the device, so a build always goes to its own board.
Otherwise the target is `arduino-tcp-host' as before."
    (interactive)
    (let* ((who (arduino--read-owner))
           (host (if (and who arduino-ota-host-format)
                     (arduino--resolve-host (format arduino-ota-host-format who))
                   (progn
                     (unless arduino-tcp-host
                       (call-interactively #'arduino-set-tcp-host))
                     arduino-tcp-host)))
           (owner (arduino--owner-flag who))
           (default-directory (arduino--sketch-dir))
           (sketch-name (file-name-nondirectory
                         (directory-file-name default-directory)))
           (build-dir "build"))
      (message "Arduino: OTA to %s%s" host (if who (format " (owner %s)" who) ""))
      (compile (format "arduino-cli compile -b %s%s --output-dir %s . && python3 %s -d -r -i %s -p %s -f %s/%s.ino.bin"
                       (arduino--fqbn)
                       owner
                       build-dir
                       (arduino--espota-script)
                       host
                       arduino-tcp-port
                       build-dir
                       sketch-name))))

  (defun arduino-serial-monitor ()
    "Open serial monitor for the Arduino."
    (interactive)
    (let ((port (arduino--port))
          (buf (get-buffer-create "*arduino-monitor*")))
      (with-current-buffer buf (erase-buffer))
      (start-process "arduino-monitor" buf
                     "arduino-cli" "monitor" "-p" port)
      (display-buffer buf)))
  :bind (:map arduino-mode-map
              ("C-c a c" . arduino-compile)
              ("C-c a u" . arduino-upload)
              ("C-c a t" . arduino-upload-tcp)
              ("C-c a s" . arduino-set-tcp-host)
              ("C-c a d" . arduino-pick-tcp-host)
              ("C-c a m" . arduino-serial-monitor)))