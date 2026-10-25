;;; lispm-mycin.el --- MYCIN, the expert system of the 1970s  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Ryan.K

;; Author: Ryan.K
;; URL: https://github.com/LispMachineLab/lispm-mycin
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (emacs-cl "0.6.0"))
;; Keywords: games, lisp
;; SPDX-License-Identifier: AGPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as published
;; by the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU Affero General Public License for more details.

;; You should have received a copy of the GNU Affero General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; MYCIN, written at Stanford in the 1970s, asked a doctor about a
;; patient and the cultures taken from them, and named the organisms
;; likely to infect the blood, each with a certainty factor.  This is
;; the MYCIN Peter Norvig rebuilt in Paradigms of Artificial
;; Intelligence Programming: its EMYCIN shell and a sample of rules, in
;; Common Lisp, unchanged in paip/, run by Emacs Common Lisp (the
;; emacs-cl package) in a batch Emacs beside this one.
;;
;; `lispm-mycin' opens a consultation.  MYCIN asks; type the answer and
;; Return.  Besides an answer it takes help, ? for the answers it
;; accepts, why for the rule it is trying, rule for that rule as it is
;; written, and unknown; and several answers with certainty factors, as
;; (neg .8 pos .2).  In LispM Desktop it is an application of the App
;; Store, with buttons for these: the desktop dresses its window from
;; its own side, with `lispm-mycin-asking-p' and `lispm-mycin-status'.

;;; Code:

(require 'comint)
(require 'easymenu)
(require 'emacs-cl)

(defgroup lispm-mycin nil
  "MYCIN, the expert system of the 1970s."
  :group 'games
  :prefix "lispm-mycin-")

(defconst lispm-mycin-directory
  (file-name-directory (or load-file-name buffer-file-name))
  "The directory of this package.")

(defvar lispm-mycin-buffer-name "*MYCIN*"
  "The name of the consultation's buffer.")

(defconst lispm-mycin-introduction
  "MYCIN names the organisms likely to infect a patient's blood, from
what you tell it about the patient and the cultures taken.  Type each
answer and Return; after the patient's name, help says what else you
can type.\n\n"
  "What a new consultation starts with.")

(defface lispm-mycin-heading '((t :weight bold))
  "Face of the headings of a consultation, as ------ PATIENT-1 ------.")

(defface lispm-mycin-finding '((t :inherit font-lock-keyword-face :weight bold))
  "Face of MYCIN's findings.")

(defvar lispm-mycin-font-lock-keywords
  '(("^------ .* ------$" . 'lispm-mycin-heading)
    ("^Findings for .*:$" . 'lispm-mycin-heading)
    ("^ [A-Z-]+: .*$" . 'lispm-mycin-finding))
  "What a consultation highlights.")

;;;; Starting

(defun lispm-mycin--file (name)
  "Return the file NAME of PAIP's MYCIN."
  (expand-file-name name (expand-file-name "paip" lispm-mycin-directory)))

(defun lispm-mycin--sentinel (process _event)
  "Say in PROCESS's buffer that the consultation is over."
  (when (and (memq (process-status process) '(exit signal))
             (buffer-live-p (process-buffer process)))
    (with-current-buffer (process-buffer process)
      (let ((inhibit-read-only t))
        (save-excursion
          (goto-char (point-max))
          (insert (if (eq 0 (process-exit-status process))
                      "\n\nThe consultation is over.  C-c C-n starts another.\n"
                    "\n\nMYCIN stopped on an error.  C-c C-n starts again.\n")))))))

(defun lispm-mycin--start (buffer)
  "Start a consultation in BUFFER."
  (with-current-buffer buffer
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert lispm-mycin-introduction)))
  (let ((process (emacs-cl-start buffer
                                 :name "mycin"
                                 :load (list (lispm-mycin--file "auxfns.lisp"))
                                 :eval (list "(requires \"mycin\" \"mycin-r\")"
                                             (format "(load %S)"
                                                     (expand-file-name "lisp/mycin.lisp"
                                                                       lispm-mycin-directory))
                                             "(mycin)"))))
    (set-process-sentinel process #'lispm-mycin--sentinel)
    process))

(defun lispm-mycin-running-p ()
  "Return non-nil while MYCIN asks, in the consultation's buffer."
  (let ((buffer (get-buffer lispm-mycin-buffer-name)))
    (and buffer (process-live-p (get-buffer-process buffer)))))

(defun lispm-mycin-asking-p ()
  "Return non-nil while MYCIN waits for an answer it reads as a value,
which why, rule, ? and unknown may take the place of.  It reads the
patient's name as a line of text, and a y or n question takes y or n."
  (when-let* ((buffer (get-buffer lispm-mycin-buffer-name))
              (process (get-buffer-process buffer))
              ((process-live-p process)))
    (with-current-buffer buffer
      (let* ((mark (process-mark process))
             ;; Comint's output is a field of its own: go past it.
             (prompt (buffer-substring-no-properties
                      (let ((inhibit-field-text-motion t))
                        (save-excursion (goto-char mark) (line-beginning-position)))
                      mark)))
        (and (string-match-p "[?:] *\\'" prompt)
             (not (string-match-p "name: *\\'\\|(y or n) *\\'" prompt)))))))

;;;###autoload
(defun lispm-mycin ()
  "Open a MYCIN consultation, going on with the one under way."
  (interactive)
  (let ((buffer (get-buffer-create lispm-mycin-buffer-name)))
    (with-current-buffer buffer
      (unless (derived-mode-p 'lispm-mycin-mode)
        (lispm-mycin-mode)))
    (unless (get-buffer-process buffer)
      (lispm-mycin--start buffer))
    (pop-to-buffer-same-window buffer)))

(defun lispm-mycin-new ()
  "Start a new consultation, ending the one under way."
  (interactive)
  (let ((buffer (get-buffer-create lispm-mycin-buffer-name)))
    (when-let* ((process (get-buffer-process buffer)))
      (set-process-sentinel process #'ignore)
      (delete-process process))
    (with-current-buffer buffer
      (unless (derived-mode-p 'lispm-mycin-mode)
        (lispm-mycin-mode)))
    (lispm-mycin--start buffer)
    (pop-to-buffer-same-window buffer)))

;;;; Answering

(defun lispm-mycin--answer (words)
  "Answer WORDS, one of why, rule, ? and unknown, to MYCIN's question."
  (unless (lispm-mycin-asking-p)
    (user-error "MYCIN takes %s only as the answer to a question about the patient" words))
  (with-current-buffer lispm-mycin-buffer-name
    (lispm-mycin-say words)))

(defun lispm-mycin-say (words)
  "Answer WORDS to MYCIN's question, as if typed."
  (let ((process (get-buffer-process (current-buffer))))
    (unless (process-live-p process)
      (user-error "No consultation is under way; C-c C-n starts one"))
    (goto-char (process-mark process))
    (delete-region (point) (point-max))
    (insert words)
    (comint-send-input)))

(defun lispm-mycin-why ()
  "Ask MYCIN why it asks: the rule it is trying."
  (interactive)
  (lispm-mycin--answer "why"))

(defun lispm-mycin-rule ()
  "Show the rule MYCIN is trying, as it is written."
  (interactive)
  (lispm-mycin--answer "rule"))

(defun lispm-mycin-choices ()
  "Ask MYCIN what answers it accepts to its question."
  (interactive)
  (lispm-mycin--answer "?"))

(defun lispm-mycin-unknown ()
  "Answer that the answer is not known."
  (interactive)
  (lispm-mycin--answer "unknown"))

(defun lispm-mycin-help ()
  "Ask MYCIN what can be typed."
  (interactive)
  (lispm-mycin--answer "help"))

;;;; Mode

(defvar-keymap lispm-mycin-mode-map
  :parent comint-mode-map
  "C-c C-n" #'lispm-mycin-new
  "C-c C-w" #'lispm-mycin-why
  "C-c C-r" #'lispm-mycin-rule
  "C-c C-c" #'lispm-mycin-choices
  "C-c C-u" #'lispm-mycin-unknown
  "C-c C-h" #'lispm-mycin-help
  ;; Comint's menus are a shell's.
  "<menu-bar> <signals>" #'undefined
  "<menu-bar> <inout>" #'undefined
  "<menu-bar> <completion>" #'undefined)

(easy-menu-define lispm-mycin-menu lispm-mycin-mode-map
  "Menu of a MYCIN consultation."
  '("MYCIN"
    ["New Consultation" lispm-mycin-new]
    "---"
    ["Why?" lispm-mycin-why (lispm-mycin-asking-p)]
    ["Show the Rule" lispm-mycin-rule (lispm-mycin-asking-p)]
    ["Possible Answers" lispm-mycin-choices (lispm-mycin-asking-p)]
    ["Unknown" lispm-mycin-unknown (lispm-mycin-asking-p)]
    ["Help" lispm-mycin-help (lispm-mycin-asking-p)]))

(define-derived-mode lispm-mycin-mode comint-mode "MYCIN"
  "Major mode of a MYCIN consultation, opened by `lispm-mycin'.
Type each answer and Return.
\\{lispm-mycin-mode-map}"
  (setq-local comint-prompt-regexp "^[^\n]*[?:] ")
  (setq-local comint-prompt-read-only t)
  (setq-local font-lock-defaults '(lispm-mycin-font-lock-keywords t))
  (font-lock-mode 1))

;;;; What the window says

(defun lispm-mycin-status ()
  "Return what a consultation's window says at its bottom."
  (if (lispm-mycin-running-p) "Consulting" "Finished"))

(provide 'lispm-mycin)
;;; lispm-mycin.el ends here
