;; set scroll to step by 1 instead of half a page.  -*- lexical-binding: t; -*-
(setq scroll-step            1
	  scroll-conservatively  10000)

(setq mouse-wheel-follow-mouse 't)
(setq mouse-wheel-scroll-amount '(1 ((shift) . 1)))

;; Scroll by pixels rather than whole lines.  Line scrolling treats an inline
;; image as one tall line, so the wheel jumped clean over org-mode pictures
;; and could never stop part way through one.  Mouse wheels are interpolated
;; into a smooth pixel scroll too (`pixel-scroll-precision-interpolate-mice').
(pixel-scroll-precision-mode 1)
