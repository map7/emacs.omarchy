;;; invoice_quickbooks.el --- Create QBO invoices from org-mode DONE items -*- lexical-binding: t; -*-

;; Scans the current org buffer for DONE headings that have no tags,
;; groups their CLOCK entries by day, and creates an invoice in
;; QuickBooks Online (Digitech Corporation) with one line per day at
;; $100/hr + 10% GST. The invoice is created but not sent.
;;
;; Bindings (inside org-mode):
;;   C-c q i  invoice-qbo-create-from-buffer
;;   C-c q p  invoice-qbo-preview-from-buffer
;;   C-c q a  invoice-qbo-authorize
;;   C-c q l  invoice-qbo-logout

(require 'json)
(require 'url)
(require 'org)
(require 'org-element)
(require 'cl-lib)

;;; -------------------------------------------------------------------
;;; Configuration

(defgroup invoice-qbo nil
  "QuickBooks Online invoicing from org-mode."
  :group 'org)

(defcustom invoice-qbo-client-id-env "REPORTCRAFT_QBO_API_CLIENT_ID"
  "Environment variable holding the QBO OAuth client id."
  :type 'string :group 'invoice-qbo)

(defcustom invoice-qbo-client-secret-env "REPORTCRAFT_QBO_API_CLIENT_SECRET"
  "Environment variable holding the QBO OAuth client secret."
  :type 'string :group 'invoice-qbo)

(defcustom invoice-qbo-company-name "Digitech Corporation"
  "Friendly name of the QBO company we expect to be authorised against."
  :type 'string :group 'invoice-qbo)

(defcustom invoice-qbo-redirect-uri "https://reportcraft.com.au/emacs-oauth"
  "OAuth redirect URI. Must match one registered for the QBO app exactly.
Intuit rejects localhost and plain http for production keys, so this
points at a path that does not exist in the ReportCraft Rails app: the
browser lands on a 404 with the auth code still in the address bar, and
nothing server-side consumes the code before we exchange it here.
Do not reuse /oauth2-redirect — companies#oauth2_redirect swaps the code
for tokens itself, and the code is single-use."
  :type 'string :group 'invoice-qbo)

(defcustom invoice-qbo-environment 'production
  "Which QBO environment to use."
  :type '(choice (const production) (const sandbox))
  :group 'invoice-qbo)

(defcustom invoice-qbo-hourly-rate 100.0
  "Default hourly rate in AUD applied to each invoice line."
  :type 'number :group 'invoice-qbo)

(defcustom invoice-qbo-gst-rate 0.10
  "GST rate. 0.10 = 10%."
  :type 'number :group 'invoice-qbo)

(defcustom invoice-qbo-terms-name "Net 30"
  "Name of the QBO Term to put on the invoice.
Matched case-insensitively, and tried before `invoice-qbo-terms-days'."
  :type 'string :group 'invoice-qbo)

(defcustom invoice-qbo-terms-days 30
  "Payment terms in days.  Matched against a QBO Term with these DueDays.
If no such Term exists, `DueDate' is set to this many days out instead."
  :type 'integer :group 'invoice-qbo)

(defcustom invoice-qbo-set-doc-number t
  "When non-nil, set DocNumber to the highest existing number plus one.
When nil, QBO assigns the invoice number itself."
  :type 'boolean :group 'invoice-qbo)

(defcustom invoice-qbo-minor-version "75"
  "QBO API minor version sent with every request.
Without one QBO answers with a very old schema in which the online
payment flags do not exist, so they are silently dropped."
  :type 'string :group 'invoice-qbo)

(defcustom invoice-qbo-online-payment-flags
  '(:AllowOnlinePayPalPayment t :AllowOnlinePayment t)
  "Online payment flags merged into the invoice payload.
`AllowOnlinePayPalPayment' is the tick box labelled \"Accept card
payments with PayPal\" on an AU company file.  It is absent from the
public Invoice docs — it showed up in `invoice-qbo-dump-invoice' output
alongside AllowOnlineAffirmPayment.  AllowOnlineCreditCardPayment and
AllowOnlineACHPayment refer to Intuit's own Payments service and are
forced back to false on a file that uses PayPal instead."
  :type '(plist :value-type boolean) :group 'invoice-qbo)

;; defcustom won't overwrite an already-bound value, so re-apply these
;; for a running Emacs that loaded an older version of this file.
(setq invoice-qbo-terms-name "Net 30")
(setq invoice-qbo-terms-days 30)
(setq invoice-qbo-set-doc-number t)
(setq invoice-qbo-minor-version "75")
(setq invoice-qbo-online-payment-flags
      '(:AllowOnlinePayPalPayment t :AllowOnlinePayment t))

(defcustom invoice-qbo-token-file
  (expand-file-name ".invoice-qbo-tokens.el" user-emacs-directory)
  "Where to persist OAuth tokens."
  :type 'file :group 'invoice-qbo)

(defcustom invoice-qbo-cache-file
  (expand-file-name ".invoice-qbo-cache.el" user-emacs-directory)
  "Where to persist chosen customer / item / tax code IDs."
  :type 'file :group 'invoice-qbo)

;;; -------------------------------------------------------------------
;;; Internal state

(defvar invoice-qbo--tokens nil
  "Plist with :access-token :refresh-token :expires-at :realm-id.")

(defvar invoice-qbo--cache nil
  "Plist with :customer-id :customer-name :item-id :item-name :tax-code-id :tax-code-name.")

(defun invoice-qbo--api-base ()
  (if (eq invoice-qbo-environment 'sandbox)
      "https://sandbox-quickbooks.api.intuit.com"
    "https://quickbooks.api.intuit.com"))

(defun invoice-qbo--getenv (var)
  "Return VAR from the environment, re-reading the shell env files if unset."
  (or (if (fboundp 'shell-env-getenv) (shell-env-getenv var) (getenv var))
      (user-error "Env var %s not set (check %s)" var
                  (if (boundp 'shell-env-files)
                      (string-join shell-env-files ", ")
                    "your shell environment"))))

(defun invoice-qbo-show-config ()
  "Show what this session will actually send to Intuit.
Values live in `defcustom's, so reloading this file does not update
them in a running Emacs — use \\[customize-set-variable] or `setq'."
  (interactive)
  (let ((id (getenv invoice-qbo-client-id-env)))
    (message
     (concat "redirect_uri: %s\nclient_id: %s (%s)\nenvironment: %s\n"
             "The redirect_uri must appear verbatim under the app's %s keys.")
     invoice-qbo-redirect-uri
     (if id (concat (substring id 0 (min 8 (length id))) "…") "UNSET")
     invoice-qbo-client-id-env
     invoice-qbo-environment
     (if (eq invoice-qbo-environment 'sandbox) "Development" "Production"))))

(defun invoice-qbo--client-id ()
  (invoice-qbo--getenv invoice-qbo-client-id-env))

(defun invoice-qbo--client-secret ()
  (invoice-qbo--getenv invoice-qbo-client-secret-env))

;;; -------------------------------------------------------------------
;;; Persistence

(defun invoice-qbo--save-tokens ()
  (with-temp-file invoice-qbo-token-file
    (set-buffer-file-coding-system 'utf-8)
    (insert ";; -*- mode: emacs-lisp; -*-\n")
    (prin1 invoice-qbo--tokens (current-buffer)))
  (set-file-modes invoice-qbo-token-file #o600))

(defun invoice-qbo--load-tokens ()
  (when (file-readable-p invoice-qbo-token-file)
    (with-temp-buffer
      (insert-file-contents invoice-qbo-token-file)
      (goto-char (point-min))
      (condition-case nil
          (setq invoice-qbo--tokens (read (current-buffer)))
        (error (setq invoice-qbo--tokens nil))))))

(defun invoice-qbo--save-cache ()
  (with-temp-file invoice-qbo-cache-file
    (insert ";; -*- mode: emacs-lisp; -*-\n")
    (prin1 invoice-qbo--cache (current-buffer))))

(defun invoice-qbo--load-cache ()
  (when (file-readable-p invoice-qbo-cache-file)
    (with-temp-buffer
      (insert-file-contents invoice-qbo-cache-file)
      (goto-char (point-min))
      (condition-case nil
          (setq invoice-qbo--cache (read (current-buffer)))
        (error (setq invoice-qbo--cache nil))))))

;;; -------------------------------------------------------------------
;;; OAuth 2.0

(defun invoice-qbo--basic-auth-header ()
  (concat "Basic "
          (base64-encode-string
           (format "%s:%s" (invoice-qbo--client-id) (invoice-qbo--client-secret))
           t)))

(defun invoice-qbo--urlencode (alist)
  (mapconcat (lambda (p)
               (format "%s=%s"
                       (url-hexify-string (car p))
                       (url-hexify-string (cdr p))))
             alist "&"))

(defun invoice-qbo--token-request (form)
  "POST FORM (alist) to the token endpoint, return parsed JSON plist."
  (let ((url-request-method "POST")
        (url-request-extra-headers
         `(("Accept" . "application/json")
           ("Content-Type" . "application/x-www-form-urlencoded")
           ("Authorization" . ,(invoice-qbo--basic-auth-header))))
        (url-request-data (invoice-qbo--urlencode form)))
    (with-current-buffer
        (url-retrieve-synchronously
         "https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer" t)
      (goto-char (point-min))
      (unless (re-search-forward "^\r?$" nil t)
        (error "Malformed token endpoint response"))
      (let* ((body (buffer-substring-no-properties (point) (point-max)))
             (json-object-type 'plist)
             (json-array-type 'list)
             (json-key-type 'keyword)
             (data (json-read-from-string body)))
        (when (plist-get data :error)
          (error "QBO token error: %s — %s"
                 (plist-get data :error)
                 (or (plist-get data :error_description) "")))
        data))))

(defun invoice-qbo--store-token-response (data &optional realm-id)
  (let ((expires (plist-get data :expires_in)))
    (setq invoice-qbo--tokens
          (list :access-token (plist-get data :access_token)
                :refresh-token (or (plist-get data :refresh_token)
                                   (plist-get invoice-qbo--tokens :refresh-token))
                :expires-at (when expires (+ (float-time) expires -30))
                :realm-id (or realm-id
                              (plist-get invoice-qbo--tokens :realm-id)))))
  (invoice-qbo--save-tokens))

(defun invoice-qbo--parse-callback (input)
  "Parse INPUT into an alist of callback parameters.
Accepts a full redirect URL, a scheme-less one, or a bare query string,
with or without surrounding whitespace and a trailing #fragment."
  (let* ((s (string-trim input))
         (query (cond
                 ((string-match "\\`[^?]*\\?\\(.*\\)\\'" s) (match-string 1 s))
                 ;; A bare "code=...&state=..." paste.
                 ((string-match-p "=" s) s))))
    (when query
      (mapcar (lambda (pair) (cons (car pair) (cadr pair)))
              (url-parse-query-string (car (split-string query "#")))))))

(defun invoice-qbo-authorize ()
  "Run the OAuth authorization-code flow interactively.
Opens a browser; user pastes the redirected URL back into Emacs."
  (interactive)
  (let* ((state (format "emacs-%d" (random 1000000)))
         (auth-url
          (concat "https://appcenter.intuit.com/connect/oauth2?"
                  (invoice-qbo--urlencode
                   `(("client_id"     . ,(invoice-qbo--client-id))
                     ("response_type" . "code")
                     ("scope"         . "com.intuit.quickbooks.accounting")
                     ("redirect_uri"  . ,invoice-qbo-redirect-uri)
                     ("state"         . ,state))))))
    (browse-url auth-url)
    (message "Opened browser. Authorize %s, then copy the URL of the 404 page you land on."
             invoice-qbo-company-name)
    (let* ((redirected
            (read-string
             "Paste the full URL you were redirected to: "))
           (params (invoice-qbo--parse-callback redirected))
           (code   (cdr (assoc "code"    params)))
           (rstate (cdr (assoc "state"   params)))
           (realm  (cdr (assoc "realmId" params)))
           (seen   (if params
                       (mapconcat #'car params ", ")
                     "none — what you pasted had no query string at all")))
      (when-let* ((err (cdr (assoc "error" params))))
        (user-error "Intuit refused the authorization: %s %s" err
                    (or (cdr (assoc "error_description" params)) "")))
      (unless code  (user-error "No `code' in the pasted URL. Parameters seen: %s" seen))
      (unless realm (user-error "No `realmId' in the pasted URL. Parameters seen: %s" seen))
      (unless (string= rstate state)
        (user-error "OAuth state mismatch — expected %s, got %s" state rstate))
      (let ((data (invoice-qbo--token-request
                   `(("grant_type"   . "authorization_code")
                     ("code"         . ,code)
                     ("redirect_uri" . ,invoice-qbo-redirect-uri)))))
        (invoice-qbo--store-token-response data realm)
        (message "Authorized. Realm: %s" realm)))))

(defun invoice-qbo--refresh ()
  (let ((rt (plist-get invoice-qbo--tokens :refresh-token)))
    (unless rt (user-error "No refresh token — run M-x invoice-qbo-authorize"))
    (let ((data (invoice-qbo--token-request
                 `(("grant_type"    . "refresh_token")
                   ("refresh_token" . ,rt)))))
      (invoice-qbo--store-token-response data))))

(defun invoice-qbo--ensure-token ()
  (unless invoice-qbo--tokens (invoice-qbo--load-tokens))
  (unless (plist-get invoice-qbo--tokens :access-token)
    (invoice-qbo-authorize))
  (let ((exp (plist-get invoice-qbo--tokens :expires-at)))
    (when (or (null exp) (< exp (float-time)))
      (invoice-qbo--refresh))))

(defun invoice-qbo-logout ()
  "Forget cached tokens (cache of customer/item/tax is kept)."
  (interactive)
  (setq invoice-qbo--tokens nil)
  (when (file-exists-p invoice-qbo-token-file)
    (delete-file invoice-qbo-token-file))
  (message "QBO tokens cleared."))

;;; -------------------------------------------------------------------
;;; HTTP

(defun invoice-qbo--request (method path &optional body params as-text)
  "METHOD = \"GET\"/\"POST\". PATH joined under /v3/company/{realm}/.
BODY is an alist/plist for JSON; PARAMS is an alist for the query string.
Returns the parsed response as a plist, or the raw body when AS-TEXT is
non-nil — re-encoding a parsed response mangles JSON arrays, so anything
displaying a record verbatim wants the text."
  (invoice-qbo--ensure-token)
  (let* ((realm (or (plist-get invoice-qbo--tokens :realm-id)
                    (user-error "No realm id — re-authorize")))
         (params (append params
                         (when invoice-qbo-minor-version
                           `(("minorversion" . ,invoice-qbo-minor-version)))))
         (qs (when params (concat "?" (invoice-qbo--urlencode params))))
         (url (format "%s/v3/company/%s/%s%s"
                      (invoice-qbo--api-base) realm path (or qs "")))
         (url-request-method method)
         (url-request-extra-headers
          `(("Authorization" . ,(concat "Bearer "
                                        (plist-get invoice-qbo--tokens :access-token)))
            ("Accept"        . "application/json")
            ,@(when body '(("Content-Type" . "application/json")))))
         (url-request-data
          (when body (encode-coding-string (json-encode body) 'utf-8))))
    (with-current-buffer (url-retrieve-synchronously url t)
      (goto-char (point-min))
      (let* ((status-line (buffer-substring (point-min) (line-end-position)))
             (code (and (string-match " \\([0-9]+\\) " status-line)
                        (string-to-number (match-string 1 status-line)))))
        (unless (re-search-forward "^\r?$" nil t)
          (error "Malformed QBO response: %s" status-line))
        (let* ((raw (buffer-substring-no-properties (point) (point-max)))
               (json-object-type 'plist)
               (json-array-type 'list)
               (json-key-type 'keyword))
          (cond
           ((and code (= code 401))
            (invoice-qbo--refresh)
            (invoice-qbo--request method path body params as-text))
           ((and code (>= code 400))
            (error "QBO %s %s -> %d: %s" method path code raw))
           ((string-empty-p (string-trim raw)) nil)
           (as-text raw)
           (t (json-read-from-string raw))))))))

(defun invoice-qbo--query (sql &optional as-text)
  "Run a QBO SQL-like query and return the parsed result.
With AS-TEXT, return the response body as it arrived."
  (invoice-qbo--request "GET" "query" nil `(("query" . ,sql)) as-text))

;;; -------------------------------------------------------------------
;;; Lookups (customer / item / tax code) with caching

(defun invoice-qbo--load-cache-once ()
  (unless invoice-qbo--cache (invoice-qbo--load-cache)))

(defun invoice-qbo--all-rows (response key)
  "Pull rows named KEY (a keyword like :Customer) out of a QBO query response."
  (let ((qr (plist-get response :QueryResponse)))
    (or (plist-get qr key) '())))

(defun invoice-qbo--pick-customer ()
  (invoice-qbo--load-cache-once)
  (or (plist-get invoice-qbo--cache :customer-id)
      (let* ((rows (invoice-qbo--all-rows
                    (invoice-qbo--query
                     "SELECT Id, DisplayName FROM Customer WHERE Active = true MAXRESULTS 500")
                    :Customer))
             (choices (mapcar (lambda (c)
                                (cons (plist-get c :DisplayName)
                                      (plist-get c :Id)))
                              rows))
             (_ (unless choices (user-error "No active customers found in QBO")))
             (pick (completing-read "Bill to customer: " choices nil t))
             (id   (cdr (assoc pick choices))))
        (setq invoice-qbo--cache
              (plist-put (or invoice-qbo--cache '())
                         :customer-id id))
        (setq invoice-qbo--cache (plist-put invoice-qbo--cache :customer-name pick))
        (invoice-qbo--save-cache)
        id)))

(defun invoice-qbo--pick-item ()
  (invoice-qbo--load-cache-once)
  (or (plist-get invoice-qbo--cache :item-id)
      (let* ((rows (invoice-qbo--all-rows
                    (invoice-qbo--query
                     "SELECT Id, Name, Type FROM Item WHERE Active = true MAXRESULTS 500")
                    :Item))
             (choices (mapcar (lambda (i)
                                (cons (format "%s (%s)"
                                              (plist-get i :Name)
                                              (plist-get i :Type))
                                      (plist-get i :Id)))
                              rows))
             (_ (unless choices (user-error "No items found in QBO")))
             (pick (completing-read "Service item: " choices nil t))
             (id   (cdr (assoc pick choices))))
        (setq invoice-qbo--cache (plist-put (or invoice-qbo--cache '()) :item-id id))
        (setq invoice-qbo--cache (plist-put invoice-qbo--cache :item-name pick))
        (invoice-qbo--save-cache)
        id)))

(defun invoice-qbo--pick-tax-code ()
  (invoice-qbo--load-cache-once)
  (or (plist-get invoice-qbo--cache :tax-code-id)
      (let* ((rows (invoice-qbo--all-rows
                    (invoice-qbo--query
                     "SELECT Id, Name, Description FROM TaxCode MAXRESULTS 500")
                    :TaxCode))
             (choices (mapcar (lambda (tc)
                                (cons (format "%s — %s"
                                              (plist-get tc :Name)
                                              (or (plist-get tc :Description) ""))
                                      (plist-get tc :Id)))
                              rows))
             (_ (unless choices (user-error "No tax codes found in QBO")))
             (default (cl-find-if (lambda (c) (string-match-p "GST" (car c))) choices))
             (pick (completing-read "GST tax code: " choices nil t
                                    (when default (car default))))
             (id   (cdr (assoc pick choices))))
        (setq invoice-qbo--cache (plist-put (or invoice-qbo--cache '()) :tax-code-id id))
        (setq invoice-qbo--cache (plist-put invoice-qbo--cache :tax-code-name pick))
        (invoice-qbo--save-cache)
        id)))

(defun invoice-qbo--customer-email (customer-id)
  "Return the primary email on CUSTOMER-ID's QBO record, or nil.
Read fresh each time rather than cached, so an address corrected in QBO
is picked up on the next invoice."
  (let* ((rows (invoice-qbo--all-rows
                (invoice-qbo--query
                 (format "SELECT Id, PrimaryEmailAddr FROM Customer WHERE Id = '%s'"
                         customer-id))
                :Customer))
         (address (plist-get (plist-get (car rows) :PrimaryEmailAddr) :Address)))
    (when (and (stringp address) (not (string-empty-p address)))
      address)))

(defconst invoice-qbo--no-term "none"
  "Cached `:term-id' meaning \"this file has no usable Term, use DueDate\".")

(defun invoice-qbo--terms ()
  "Return the active Terms defined in the company file."
  (invoice-qbo--all-rows
   (invoice-qbo--query
    "SELECT Id, Name, DueDays FROM Term WHERE Active = true MAXRESULTS 100")
   :Term))

(defun invoice-qbo--term-days (term)
  "Return TERM's DueDays as a number, coping with it arriving as a string."
  (let ((days (plist-get term :DueDays)))
    (cond ((numberp days) days)
          ((stringp days) (string-to-number days)))))

(defconst invoice-qbo--payment-fields
  '(:AllowOnlinePayPalPayment :AllowOnlinePayment :AllowOnlineCreditCardPayment
    :AllowIPNPayment :AllowOnlineACHPayment :AllowOnlineAffirmPayment)
  "Invoice fields that between them drive the online-payment tick boxes.")

(defun invoice-qbo--show-json (title text)
  "Display TEXT, a raw JSON string, pretty-printed in a buffer named TITLE."
  (let ((buf (get-buffer-create title)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert text)
        (json-pretty-print-buffer)
        (goto-char (point-min))
        (when (fboundp 'js-mode) (js-mode))
        (view-mode 1)))
    (display-buffer buf)))

(defun invoice-qbo-dump-invoice (doc-number)
  "Show the raw QBO record for the invoice numbered DOC-NUMBER.
Use this to compare an invoice created in the QBO web UI with the
\"Accept card payments\" box ticked against one created from here: the
field that differs is the one that drives the box."
  (interactive "sInvoice number: ")
  (let* ((sql (format "SELECT * FROM Invoice WHERE DocNumber = '%s'" doc-number))
         (inv (car (invoice-qbo--all-rows (invoice-qbo--query sql) :Invoice))))
    (unless inv (user-error "No invoice numbered %s in this company file" doc-number))
    (message "#%s payment fields: %s"
             doc-number
             (mapconcat (lambda (field)
                          (format "%s=%S" (substring (symbol-name field) 1)
                                  (plist-get inv field)))
                        invoice-qbo--payment-fields "  "))
    (invoice-qbo--show-json (format "*invoice-qbo #%s*" doc-number)
                            (invoice-qbo--query sql t))))

(defun invoice-qbo-enable-paypal (doc-number)
  "Turn on the online payment flags for the existing invoice DOC-NUMBER.
Sends a sparse update, then reads the invoice back and reports what QBO
actually stored — which is the test of whether the flags are settable
through the API on this company file at all."
  (interactive "sInvoice number: ")
  (let* ((sql (format "SELECT * FROM Invoice WHERE DocNumber = '%s'" doc-number))
         (inv (car (invoice-qbo--all-rows (invoice-qbo--query sql) :Invoice))))
    (unless inv (user-error "No invoice numbered %s in this company file" doc-number))
    (invoice-qbo--request
     "POST" "invoice"
     (append `(:Id ,(plist-get inv :Id)
               :SyncToken ,(plist-get inv :SyncToken)
               :sparse t)
             (copy-sequence invoice-qbo-online-payment-flags)))
    (let ((after (car (invoice-qbo--all-rows (invoice-qbo--query sql) :Invoice))))
      (message "#%s now: %s"
               doc-number
               (mapconcat (lambda (field)
                            (format "%s=%S" (substring (symbol-name field) 1)
                                    (plist-get after field)))
                          invoice-qbo--payment-fields "  ")))))

(defun invoice-qbo--invoice-by-number (doc-number)
  "Return the QBO invoice record numbered DOC-NUMBER."
  (car (invoice-qbo--all-rows
        (invoice-qbo--query
         (format "SELECT * FROM Invoice WHERE DocNumber = '%s'" doc-number))
        :Invoice)))

(defun invoice-qbo-probe-payment-flags (doc-number)
  "Set each online payment flag on invoice DOC-NUMBER one at a time.
After each sparse update the invoice is read back, so the report says
which flags QBO actually stores rather than which it merely accepts.
The invoice is left with whichever flags stuck."
  (interactive "sInvoice number: ")
  (let (results)
    (dolist (field invoice-qbo--payment-fields)
      (let ((inv (invoice-qbo--invoice-by-number doc-number)))
        (unless inv (user-error "No invoice numbered %s" doc-number))
        ;; SyncToken moves with every accepted update, so re-read it each time.
        (invoice-qbo--request
         "POST" "invoice"
         (list :Id (plist-get inv :Id)
               :SyncToken (plist-get inv :SyncToken)
               :sparse t
               field t))
        (push (cons field (plist-get (invoice-qbo--invoice-by-number doc-number)
                                     field))
              results)))
    (with-output-to-temp-buffer "*invoice-qbo payment flags*"
      (princ (format "Invoice #%s, minorversion %s\n"
                     doc-number invoice-qbo-minor-version))
      (princ "Each flag set on its own, then read back:\n\n")
      (dolist (r (nreverse results))
        (princ (format "  %-32s -> %s\n"
                       (substring (symbol-name (car r)) 1)
                       (if (eq (cdr r) t) "STORED true" "refused")))))))

(defun invoice-qbo-check-settings ()
  "Report the QBO company settings that govern terms and invoice numbers.
QBO silently ignores a DocNumber we send unless \"Custom transaction
numbers\" is switched on under Account and settings > Sales."
  (interactive)
  (let* ((prefs (car (invoice-qbo--all-rows
                      (invoice-qbo--query "SELECT * FROM Preferences")
                      :Preferences)))
         (sales (plist-get prefs :SalesFormsPrefs))
         (custom-numbers (plist-get sales :CustomTxnNumbers))
         (default-terms (plist-get sales :DefaultTerms))
         (payments (plist-get sales :ETransactionPaymentEnabled))
         (rows (invoice-qbo--terms)))
    (with-output-to-temp-buffer "*invoice-qbo settings*"
      ;; AllowOnlinePayPalPayment is only writable when this is on AND the
      ;; company has an active PayPal subscription.  Without it QBO accepts
      ;; the flag and stores false, which is what we kept seeing.
      (princ (format "ETransactionPaymentEnabled: %s\n"
                     (if (eq payments t)
                         "ON — the PayPal tick box is settable from here"
                       (concat "OFF — QBO will refuse AllowOnlinePayPalPayment.\n"
                               "    Enable online payments on the company and "
                               "onboard PayPal\n    with an ACTIVE subscription, "
                               "then the flag starts working."))))
      (princ (format "Custom transaction numbers: %s\n"
                     (if (eq custom-numbers t)
                         "ON — DocNumber we send is honoured"
                       (concat "OFF — QBO assigns invoice numbers itself and "
                               "ignores ours.\n    Turn it on at Account and "
                               "settings > Sales > Sales form content."))))
      ;; DefaultTerms arrives as a bare {"value": "4"} reference, so the
      ;; name has to come from the Term list.
      (princ (format "Company default terms: %s\n"
                     (let ((id (plist-get default-terms :value)))
                       (or (plist-get default-terms :name)
                           (cl-loop for tm in rows
                                    when (equal (plist-get tm :Id) id)
                                    return (format "%s (Id %s)"
                                                   (plist-get tm :Name) id))
                           "none"))))
      (princ (format "\nWanted term: %S (or %d days)\n"
                     invoice-qbo-terms-name invoice-qbo-terms-days))
      (if rows
          (dolist (tm rows)
            (princ (format "  Id %-4s  DueDays %-6s  %s\n"
                           (plist-get tm :Id)
                           (or (plist-get tm :DueDays) "—")
                           (plist-get tm :Name))))
        (princ "  No active terms in this company file.\n"))
      (princ (format "\nNext invoice number we would use: %s\n"
                     (invoice-qbo--next-doc-number)))
      (princ "\nSales form preferences (payment-related keys named here):\n")
      ;; Printed from the raw body: re-encoding the parsed response turns
      ;; JSON arrays into objects with repeated keys.
      (princ (with-temp-buffer
               (insert (or (invoice-qbo--query "SELECT * FROM Preferences" t) ""))
               (json-pretty-print-buffer)
               (buffer-string))))))

(defun invoice-qbo-list-terms ()
  "Show the Terms defined in the QBO company file."
  (interactive)
  (let ((rows (invoice-qbo--terms)))
    (with-output-to-temp-buffer "*invoice-qbo terms*"
      (princ (format "Looking for a term of %d days.\n\n" invoice-qbo-terms-days))
      (if rows
          (dolist (tm rows)
            (princ (format "  Id %-4s  DueDays %-6s  %s\n"
                           (plist-get tm :Id)
                           (or (plist-get tm :DueDays) "—")
                           (plist-get tm :Name))))
        (princ "  No active terms in this company file.\n")))))

(defun invoice-qbo--pick-term ()
  "Return the Id of the QBO Term to bill against.
Tried in order: the name in `invoice-qbo-terms-name', a term whose
DueDays is `invoice-qbo-terms-days', then the day count appearing in a
term's name (\"Net 30\", \"30 days\").  Falls back to asking, since a
wrong guess here silently leaves the Terms field blank on the invoice.
Returns nil when there is no usable term, and the caller sets DueDate."
  (invoice-qbo--load-cache-once)
  (let ((cached (plist-get invoice-qbo--cache :term-id)))
    (if cached
        (unless (equal cached invoice-qbo--no-term) cached)
      (let* ((rows (invoice-qbo--terms))
             (days invoice-qbo-terms-days)
             (name-re (format "\\b%d\\b" days))
             (match
              (or (cl-find-if (lambda (tm)
                                (string-equal-ignore-case
                                 (or (plist-get tm :Name) "")
                                 invoice-qbo-terms-name))
                              rows)
                  (cl-find-if (lambda (tm) (eql (invoice-qbo--term-days tm) days)) rows)
                  (cl-find-if (lambda (tm)
                                (string-match-p name-re (or (plist-get tm :Name) "")))
                              rows)))
             (id (cond
                  (match (plist-get match :Id))
                  ;; Nothing matched but terms exist — let the user say which.
                  (rows
                   (let* ((choices
                           (append
                            (mapcar (lambda (tm)
                                      (cons (format "%s (DueDays %s)"
                                                    (plist-get tm :Name)
                                                    (or (plist-get tm :DueDays) "—"))
                                            (plist-get tm :Id)))
                                    rows)
                            (list (cons "— none: set DueDate instead —"
                                        invoice-qbo--no-term))))
                          (pick (completing-read
                                 (format "No %d-day term found. Use which term? " days)
                                 choices nil t)))
                     (cdr (assoc pick choices))))
                  (t invoice-qbo--no-term))))
        (setq invoice-qbo--cache (plist-put (or invoice-qbo--cache '()) :term-id id))
        (setq invoice-qbo--cache
              (plist-put invoice-qbo--cache :term-name
                         (if match (plist-get match :Name) id)))
        (invoice-qbo--save-cache)
        (unless (equal id invoice-qbo--no-term) id)))))

(defun invoice-qbo--due-date ()
  "Return today plus `invoice-qbo-terms-days' as YYYY-MM-DD."
  (format-time-string "%Y-%m-%d"
                      (time-add (current-time)
                                (days-to-time invoice-qbo-terms-days))))

(defconst invoice-qbo--doc-number-page 1000
  "Rows per page when scanning invoices for the highest DocNumber.")

(defun invoice-qbo--next-doc-number ()
  "Return the next invoice number: the highest numeric DocNumber plus one.
Pages through every invoice because QBO can only sort DocNumber as a
string, which would rank \"999\" above \"1000\".  Non-numeric numbers are
ignored.  Zero padding on the highest number is preserved."
  (let ((start 1) (highest nil) (width 1) (pages 0) (done nil))
    (while (and (not done) (< pages 50))
      (let* ((rows (invoice-qbo--all-rows
                    (invoice-qbo--query
                     (format "SELECT DocNumber FROM Invoice STARTPOSITION %d MAXRESULTS %d"
                             start invoice-qbo--doc-number-page))
                    :Invoice)))
        (dolist (row rows)
          (let ((dn (plist-get row :DocNumber)))
            (when (and (stringp dn) (string-match-p "\\`[0-9]+\\'" dn))
              (let ((n (string-to-number dn)))
                (when (or (null highest) (> n highest))
                  (setq highest n
                        width (length dn)))))))
        (cl-incf pages)
        (if (< (length rows) invoice-qbo--doc-number-page)
            (setq done t)
          (setq start (+ start invoice-qbo--doc-number-page)))))
    (unless done
      (message "invoice-qbo: stopped scanning invoices after %d pages" pages))
    (format (format "%%0%dd" width) (1+ (or highest 0)))))

(defun invoice-qbo-reset-cache ()
  "Forget cached customer / item / tax code selections."
  (interactive)
  (setq invoice-qbo--cache nil)
  (when (file-exists-p invoice-qbo-cache-file)
    (delete-file invoice-qbo-cache-file))
  (message "Invoice QBO selections cleared."))

;;; -------------------------------------------------------------------
;;; Org parsing — untagged DONE items with clocks grouped by day

(defun invoice-qbo--collect-tasks ()
  "Return list of plists (:title STR :assigned-date \"YYYY-MM-DD\"
:minutes N :marker M) for every untagged DONE heading.  Total minutes
are summed across all CLOCK rows; the assigned date is the date of the
most recent clock-in.  Marker points at the heading start."
  (let (tasks)
    (org-element-map (org-element-parse-buffer 'headline) 'headline
      (lambda (hl)
        (when (and (string= (org-element-property :todo-keyword hl) "DONE")
                   (null (org-element-property :tags hl)))
          (let ((title (org-element-property :raw-value hl))
                (beg   (org-element-property :begin hl))
                (end   (org-element-property :end hl))
                (total 0)
                latest-stamp latest-date)
            (save-excursion
              (goto-char beg)
              (let ((limit (save-excursion (goto-char end) (point))))
                (while (re-search-forward
                        "^[ \t]*CLOCK:[ \t]*\\[\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)[^ ]* +[A-Za-z]+ +\\([0-9]\\{2\\}:[0-9]\\{2\\}\\)\\][ \t]*--[ \t]*\\[[^]]*\\][ \t]*=>[ \t]*\\([0-9]+\\):\\([0-9]\\{2\\}\\)"
                        limit t)
                  (let* ((date  (match-string 1))
                         (time  (match-string 2))
                         (stamp (concat date " " time))
                         (hh    (string-to-number (match-string 3)))
                         (mm    (string-to-number (match-string 4)))
                         (mins  (+ (* hh 60) mm)))
                    (cl-incf total mins)
                    (when (or (null latest-stamp) (string> stamp latest-stamp))
                      (setq latest-stamp stamp
                            latest-date  date))))))
            (when latest-date
              (push (list :title title
                          :assigned-date latest-date
                          :minutes total
                          :marker (copy-marker beg))
                    tasks))))))
    (nreverse tasks)))

(defun invoice-qbo--group-by-day (tasks)
  "Group TASKS by :assigned-date into ((DATE . ((TITLE . MINUTES) ...)) ...).
Returned alist is sorted by date ascending."
  (let ((tbl (make-hash-table :test 'equal)))
    (dolist (tk tasks)
      (let* ((d (plist-get tk :assigned-date))
             (title (plist-get tk :title))
             (mins  (plist-get tk :minutes)))
        (puthash d (append (gethash d tbl) (list (cons title mins))) tbl)))
    (sort (let (out)
            (maphash (lambda (d v) (push (cons d v) out)) tbl)
            out)
          (lambda (a b) (string< (car a) (car b))))))

(defun invoice-qbo--day-description (titles-mins)
  "Build a description line from ((TITLE . MINUTES) ...) for one day."
  (mapconcat (lambda (tm)
               (format "- %s (%s)"
                       (car tm)
                       (invoice-qbo--fmt-hours (cdr tm))))
             titles-mins
             "\n"))

(defun invoice-qbo--fmt-hours (minutes)
  (format "%d:%02d" (/ minutes 60) (mod minutes 60)))

(defun invoice-qbo--day-hours (titles-mins)
  (/ (apply #'+ (mapcar #'cdr titles-mins)) 60.0))

;;; -------------------------------------------------------------------
;;; Invoice payload + create

(defun invoice-qbo--day-minutes (work)
  "Total minutes in WORK, a list of (TITLE . MINUTES)."
  (apply #'+ (mapcar #'cdr work)))

(defun invoice-qbo--line-cents (grouped)
  "Return the amount in whole cents for each day in GROUPED.
Rounding every day on its own drifts from the true total — twelve lines
cost three cents on invoice 1012 — so the difference is handed out a
cent at a time to the days that lost the most to rounding.  The list
therefore sums to the total of the underlying minutes, exactly."
  (let* ((exact (mapcar (lambda (day)
                          (/ (* (invoice-qbo--day-minutes (cdr day))
                                invoice-qbo-hourly-rate 100.0)
                             60.0))
                        grouped))
         (cents (mapcar #'round exact))
         (target (round (apply #'+ exact)))
         (delta (- target (apply #'+ cents))))
    (unless (zerop delta)
      (let ((order (sort (number-sequence 0 (1- (length exact)))
                         (lambda (a b)
                           (let ((ra (- (nth a exact) (nth a cents)))
                                 (rb (- (nth b exact) (nth b cents))))
                             ;; Short: favour whoever was rounded down
                             ;; hardest.  Over: take back from whoever was
                             ;; rounded up hardest.
                             (if (> delta 0) (> ra rb) (< ra rb))))))
            (step (if (> delta 0) 1 -1)))
        (dotimes (i (min (abs delta) (length order)))
          (let ((idx (nth i order)))
            (setf (nth idx cents) (+ (nth idx cents) step))))))
    cents))

(defun invoice-qbo--build-lines (grouped item-id tax-code-id cents)
  "Return a vector of invoice line objects, one per day in GROUPED.
CENTS supplies each line's amount, from `invoice-qbo--line-cents'.
Qty is derived from that amount so Qty x UnitPrice matches it exactly
and QBO cannot recompute a different figure.
A vector, not a list: `json-encode' sees a list of plists as an alist
\(each plist is a cons with an atom car) and would emit a JSON object
with repeated keys instead of an array."
  (vconcat
   (cl-mapcar
    (lambda (day amount-cents)
      (let* ((date   (car day))
             (work   (cdr day))
             (amount (/ amount-cents 100.0))
             (qty    (/ amount invoice-qbo-hourly-rate))
             (desc   (format "%s\n%s" date (invoice-qbo--day-description work))))
        `(:DetailType "SalesItemLineDetail"
          :Amount ,amount
          :Description ,desc
          :SalesItemLineDetail
          (:ItemRef     (:value ,item-id)
           :Qty         ,qty
           :UnitPrice   ,invoice-qbo-hourly-rate
           :TaxCodeRef  (:value ,tax-code-id)))))
    grouped cents)))

(defun invoice-qbo--build-payload (grouped customer-id item-id tax-code-id
                                           &optional term-id doc-number email)
  "Build the invoice payload.
TERM-ID sets the payment terms; without one, DueDate carries the same
number of days.  DOC-NUMBER, when given, sets the invoice number.
EMAIL, when given, becomes the invoice's BillEmail."
  (append
   `(:CustomerRef (:value ,customer-id)
     :Line ,(invoice-qbo--build-lines grouped item-id tax-code-id
                                      (invoice-qbo--line-cents grouped))
     :TxnTaxDetail (:TxnTaxCodeRef (:value ,tax-code-id))
     :GlobalTaxCalculation "TaxExcluded")
   (if term-id
       `(:SalesTermRef (:value ,term-id))
     `(:DueDate ,(invoice-qbo--due-date)))
   (when doc-number `(:DocNumber ,doc-number))
   (when email `(:BillEmail (:Address ,email)))
   (copy-sequence invoice-qbo-online-payment-flags)))

(defun invoice-qbo--summarise (grouped)
  "Summarise GROUPED using the same figures the invoice will carry.
GST is summed per line rather than taken off the subtotal, because that
is how QBO computes it — doing it either other way leaves the preview
disagreeing with the invoice by a cent or two."
  (let* ((cents   (invoice-qbo--line-cents grouped))
         (sub-c   (apply #'+ cents))
         (gst-c   (apply #'+ (mapcar (lambda (c)
                                       (round (* c invoice-qbo-gst-rate)))
                                     cents)))
         (total-mins (apply #'+ (mapcar (lambda (d)
                                          (invoice-qbo--day-minutes (cdr d)))
                                        grouped))))
    (list :days (length grouped)
          :hours (/ total-mins 60.0)
          :subtotal (/ sub-c 100.0)
          :gst (/ gst-c 100.0)
          :total (/ (+ sub-c gst-c) 100.0))))

(defun invoice-qbo--iso-to-dmy (iso)
  "Convert YYYY-MM-DD to dd/mm/yyyy."
  (format "%s/%s/%s"
          (substring iso 8 10)
          (substring iso 5 7)
          (substring iso 0 4)))

(defcustom invoice-qbo-description-max 150
  "Maximum visible width for the description column in the preview."
  :type 'integer :group 'invoice-qbo)
;; defcustom won't overwrite an already-bound value, so re-apply on
;; eval-buffer during development.
(setq invoice-qbo-description-max 150)

(defun invoice-qbo--summarise-titles (titles max)
  "Join TITLES with commas; if longer than MAX, keep a fitting prefix
and append \" (+N more)\" for the dropped ones."
  (let ((full (mapconcat #'identity titles ", ")))
    (if (<= (length full) max) full
      (let ((kept '()) (used 0) (dropped 0))
        (dolist (tt titles)
          (let* ((sep (if kept ", " ""))
                 (need (+ (length sep) (length tt))))
            (if (and (zerop dropped)
                     (<= (+ used need) (- max 12))) ; leave room for " (+N more)"
                (progn (push tt kept) (cl-incf used need))
              (cl-incf dropped))))
        (concat (mapconcat #'identity (nreverse kept) ", ")
                (format " (+%d more)" dropped))))))

(defun invoice-qbo-preview-from-buffer ()
  "Show what would be invoiced without contacting QBO.
One line per day: date, comma-joined titles, hours, rate, GST, total.
Descriptions over `invoice-qbo-description-max' are summarised."
  (interactive)
  (let* ((entries (invoice-qbo--collect-tasks))
         (grouped (invoice-qbo--group-by-day entries))
         (sum (invoice-qbo--summarise grouped))
         (buf (get-buffer-create "*Invoice QBO Preview*"))
         (rows (cl-mapcar
                (lambda (day amount-cents)
                  (let* ((work (cdr day))
                         (hrs  (invoice-qbo--day-hours work))
                         (total (/ (+ amount-cents
                                      (round (* amount-cents invoice-qbo-gst-rate)))
                                   100.0)))
                    (list (invoice-qbo--iso-to-dmy (car day))
                          (mapconcat #'car work ", ")
                          hrs
                          total)))
                grouped (invoice-qbo--line-cents grouped)))
         (desc-w  (apply #'max 11 (mapcar (lambda (r) (length (nth 1 r))) rows)))
         (hrs-w   (apply #'max  5 (mapcar (lambda (r) (length (format "%.2f" (nth 2 r)))) rows)))
         (total-w (apply #'max  8 (mapcar (lambda (r) (length (format "%.2f" (nth 3 r)))) rows)))
         (fmt (format "%%-10s  %%-%ds  %%%ds  RATE=%%.2f GST=%%.2f  TOTAL=%%%ds\n"
                      desc-w hrs-w total-w)))
    (unless grouped (user-error "No untagged DONE entries with CLOCK rows found"))
    (with-current-buffer buf
      (erase-buffer)
      (dolist (r rows)
        (insert (format fmt
                        (nth 0 r)
                        (nth 1 r)
                        (format "%.2f" (nth 2 r))
                        invoice-qbo-hourly-rate
                        invoice-qbo-gst-rate
                        (format "%.2f" (nth 3 r)))))
      (insert (format "\nDays: %d   Hours: %.2f   Subtotal: $%.2f   GST: $%.2f   Total: $%.2f\n"
                      (plist-get sum :days)
                      (plist-get sum :hours)
                      (plist-get sum :subtotal)
                      (plist-get sum :gst)
                      (plist-get sum :total)))
      (goto-char (point-min)))
    (display-buffer buf)))

(defun invoice-qbo--bump-doc-number (doc-number)
  "Return DOC-NUMBER incremented by one, keeping its zero padding."
  (format (format "%%0%dd" (length doc-number))
          (1+ (string-to-number doc-number))))

(defun invoice-qbo--post-invoice (payload)
  "POST PAYLOAD to QBO, retrying with the next number if ours is taken.
QBO only rejects duplicates when custom transaction numbers are on, but
another invoice can be raised between our scan and this POST."
  (let ((attempts 0) (resp nil))
    (while (null resp)
      (cl-incf attempts)
      (condition-case err
          (setq resp (invoice-qbo--request "POST" "invoice" payload))
        (error
         (let ((doc-number (plist-get payload :DocNumber)))
           (if (and doc-number
                    (< attempts 5)
                    (string-match-p "Duplicate Document Number"
                                    (error-message-string err)))
               (let ((next (invoice-qbo--bump-doc-number doc-number)))
                 (message "invoice-qbo: #%s taken, trying #%s" doc-number next)
                 (setq payload (plist-put payload :DocNumber next)))
             (signal (car err) (cdr err)))))))
    resp))

(defvar-local invoice-qbo--last-invoice nil
  "Plist holding the most recent invoice created from this buffer.
Keys: :doc-number :id :tasks (list of plists from `invoice-qbo--collect-tasks').")

(defun invoice-qbo-create-from-buffer ()
  "Create a draft invoice in QBO from the current `org-mode' buffer.
Lines: one per day.  Rate $100/h, 10% GST.  Invoice is not sent.
After creation, the task list and invoice number are stashed so that
`invoice-qbo-mark-invoiced' can tag the source headings."
  (interactive)
  (let* ((tasks   (invoice-qbo--collect-tasks))
         (grouped (invoice-qbo--group-by-day tasks)))
    (unless grouped
      (user-error "No untagged DONE entries with CLOCK rows found"))
    (let* ((sum (invoice-qbo--summarise grouped))
           (_   (unless (yes-or-no-p
                         (format "Create draft invoice: %d day(s), %.2fh, $%.2f + GST $%.2f = $%.2f? "
                                 (plist-get sum :days)
                                 (plist-get sum :hours)
                                 (plist-get sum :subtotal)
                                 (plist-get sum :gst)
                                 (plist-get sum :total)))
                  (user-error "Cancelled")))
           (src-buf (current-buffer))
           (customer-id (invoice-qbo--pick-customer))
           (item-id     (invoice-qbo--pick-item))
           (tax-id      (invoice-qbo--pick-tax-code))
           (term-id     (invoice-qbo--pick-term))
           (doc-number  (when invoice-qbo-set-doc-number
                          (invoice-qbo--next-doc-number)))
           (email       (invoice-qbo--customer-email customer-id))
           (payload (invoice-qbo--build-payload grouped customer-id item-id tax-id
                                                term-id doc-number email))
           (resp (invoice-qbo--post-invoice payload))
           (inv  (plist-get resp :Invoice)))
      (if inv
          (progn
            ;; Only now that QBO has accepted the invoice do we touch the
            ;; org file — a failed POST must leave the headings untagged
            ;; so the next run picks them up again.
            (with-current-buffer src-buf
              (setq invoice-qbo--last-invoice
                    (list :doc-number (plist-get inv :DocNumber)
                          :id         (plist-get inv :Id)
                          :tasks      tasks))
              (invoice-qbo-mark-invoiced))
            (message "invoice-qbo: PayPal flag on the new invoice: %s"
                     (if (eq (plist-get inv :AllowOnlinePayPalPayment) t)
                         "true"
                       "false — QBO refused it at creation too"))
            (when (and doc-number
                       (not (equal doc-number (plist-get inv :DocNumber))))
              (message "invoice-qbo: asked for #%s, QBO used #%s — run M-x invoice-qbo-check-settings"
                       doc-number (or (plist-get inv :DocNumber) "(blank)")))
            (message "QBO invoice #%s created (id %s) — total $%s, terms %s, email %s. Not sent. Headings tagged :%s:"
                     (plist-get inv :DocNumber)
                     (plist-get inv :Id)
                     (plist-get inv :TotalAmt)
                     (or (plist-get invoice-qbo--cache :term-name) "DueDate only")
                     (or email "none on customer record")
                     (invoice-qbo--invoice-tag (plist-get inv :DocNumber))))
        (message "QBO response: %S" resp)))))

(defun invoice-qbo--sanitise-tag (s)
  "Convert S into something safe to use as an org tag.
Org tags allow alphanumerics plus _ @ # and %, so the # in `inv#123'
survives."
  (let ((out (replace-regexp-in-string "[^A-Za-z0-9_@#%]" "_" s)))
    (if (string-match-p "\\`[A-Za-z@_]" out) out (concat "n" out))))

(defun invoice-qbo--invoice-tag (doc-number)
  "Return the org tag for invoice DOC-NUMBER, e.g. `inv#1043'."
  (invoice-qbo--sanitise-tag (format "inv#%s" doc-number)))

(defun invoice-qbo-mark-invoiced ()
  "Tag the headings of the last invoice with :inv#DOCNUMBER:.
Uses the data stashed by `invoice-qbo-create-from-buffer', which calls
this automatically once QBO has accepted the invoice.  Adds an
`INVOICE_NUMBER' property and the org tag so future runs will skip
these entries (they are no longer untagged)."
  (interactive)
  (unless invoice-qbo--last-invoice
    (user-error "No recent invoice in this buffer — run C-c q i first"))
  (let* ((doc   (plist-get invoice-qbo--last-invoice :doc-number))
         (tasks (plist-get invoice-qbo--last-invoice :tasks))
         (tag   (invoice-qbo--invoice-tag doc))
         (count 0))
    (save-excursion
      (dolist (task tasks)
        (let ((m (plist-get task :marker)))
          (when (and m (marker-position m))
            (goto-char m)
            (when (and (org-at-heading-p)
                       (string= (org-get-todo-state) "DONE")
                       (null (org-get-tags nil t)))
              (org-set-tags (list tag))
              (org-entry-put (point) "INVOICE_NUMBER" (format "%s" doc))
              (cl-incf count))))))
    (message "Tagged %d heading(s) with :%s:" count tag)))

;;; -------------------------------------------------------------------
;;; Keybindings

(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-c q i") #'invoice-qbo-create-from-buffer)
  (define-key org-mode-map (kbd "C-c q p") #'invoice-qbo-preview-from-buffer)
  (define-key org-mode-map (kbd "C-c q m") #'invoice-qbo-mark-invoiced)
  (define-key org-mode-map (kbd "C-c q a") #'invoice-qbo-authorize)
  (define-key org-mode-map (kbd "C-c q l") #'invoice-qbo-logout)
  (when (fboundp 'shell-env-reload)
    (define-key org-mode-map (kbd "C-c q e") #'shell-env-reload)))

(provide 'invoice_quickbooks)
;;; invoice_quickbooks.el ends here
