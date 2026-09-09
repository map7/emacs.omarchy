;;; -*- lexical-binding: t; -*-
(use-package whisper
  :straight (whisper :type git :host github :repo "natrys/whisper.el")
  ;; f12 now toggles the org clock (40-org.el); whisper stays on C-c w.
  :bind (("C-c w" . whisper-run))
  :config
  (setq whisper-install-directory "~/src/whisper.cpp"
        whisper-model "base.en"
        whisper-language "en"
        whisper-translate nil
        whisper-use-threads 8))
