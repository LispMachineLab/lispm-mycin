;;; lispm-mycin-test.el --- Tests of lispm-mycin.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Ryan.K
;; SPDX-License-Identifier: AGPL-3.0-or-later

;;; Commentary:

;; Runs consultations in a batch Emacs, as `lispm-mycin' does, with
;; Common Lisp built in a temporary directory.

;;; Code:

(require 'ert)
(require 'lispm-mycin)

(defvar lispm-mycin-test-build (make-temp-file "lispm-mycin-test-build-" t)
  "The build directory of Common Lisp for the tests.")

(defvar-local lispm-mycin-test--from nil
  "Where the next wait looks from: comint moves point with the output.")

(defun lispm-mycin-test-wait-for (regexp &optional seconds)
  "Wait until the consultation's buffer holds a match for REGEXP after
the last one waited for; return non-nil when it came within SECONDS."
  (unless lispm-mycin-test--from
    (setq lispm-mycin-test--from (copy-marker (point-min))))
  (let ((end (+ (float-time) (or seconds 120)))
        found)
    (while (and (not (setq found (save-excursion
                                   (goto-char lispm-mycin-test--from)
                                   (re-search-forward regexp nil t))))
                (< (float-time) end))
      (accept-process-output (get-buffer-process (current-buffer)) 0.1))
    (if found
        (set-marker lispm-mycin-test--from found)
      ;; What MYCIN and its Emacs said, for a failure in CI.
      (message "No %S in:\n%s\nErrors:\n%s" regexp (buffer-string)
               (if-let* ((errors (get-buffer " *mycin errors*")))
                   (with-current-buffer errors (buffer-string))
                 "")))
    found))

(defun lispm-mycin-test-answer (regexp answer)
  "Wait for the question matching REGEXP and answer ANSWER."
  (should (lispm-mycin-test-wait-for regexp))
  (lispm-mycin-say answer))

(defmacro lispm-mycin-test-consultation (&rest body)
  "Run BODY in a new consultation's buffer, and end it after."
  `(let ((emacs-cl-build-directory lispm-mycin-test-build))
     (save-window-excursion
       (lispm-mycin-new)
       (with-current-buffer lispm-mycin-buffer-name
         (unwind-protect (progn ,@body)
           (let ((process (get-buffer-process (current-buffer))))
             (when process (set-process-sentinel process #'ignore) (delete-process process)))
           (kill-buffer))))))

(ert-deftest lispm-mycin-consultation ()
  "A consultation as in PAIP: MYCIN names the organisms and ends."
  (lispm-mycin-test-consultation
   (should (string-prefix-p "MYCIN names the organisms" (buffer-string)))
   ;; The name is read as a line: why there would be a name.
   (should (lispm-mycin-test-wait-for "Patient's name: "))
   (should-not (lispm-mycin-asking-p))
   (should-error (lispm-mycin-why) :type 'user-error)
   (lispm-mycin-say "Sylvia Fischer")
   (should (lispm-mycin-test-wait-for "Sex: "))
   (should (lispm-mycin-asking-p))
   ;; An answer MYCIN cannot read asks again, rather than ending it.
   (lispm-mycin-say "(male .5, female .5)")
   (should (lispm-mycin-test-wait-for "MYCIN cannot read that answer"))
   (should (lispm-mycin-test-wait-for "Sex: "))
   (lispm-mycin-say "female")
   (lispm-mycin-test-answer "Age: " "27")
   (lispm-mycin-test-answer "taken\\? " "blood")
   (lispm-mycin-test-answer "obtained\\? " "3")
   (lispm-mycin-test-answer "ORGANISM-1: " "unknown")
   (lispm-mycin-test-answer "The gram stain of ORGANISM-1: " "neg")
   (lispm-mycin-test-answer "rod or coccus (etc\\.): " "rod")
   ;; Why prints the rule MYCIN tries, in its own words.
   (lispm-mycin-test-answer "What is the AEROBICITY of ORGANISM-1\\? " "why")
   (should (lispm-mycin-test-wait-for "Rule 107:"))
   (should (lispm-mycin-test-wait-for "Then there is suggestive evidence (0\\.8) that"))
   (lispm-mycin-test-answer "What is the AEROBICITY of ORGANISM-1\\? " "aerobic")
   (lispm-mycin-test-answer "Is Sylvia Fischer a compromised host\\? " "yes")
   (lispm-mycin-test-answer "If so, mild or serious\\? " "serious")
   ;; Rules 107 and 52, then 75 with 52, as in the book.
   (should (lispm-mycin-test-wait-for
            "IDENTITY: ENTEROBACTERIACEAE (0\\.800) +PSEUDOMONAS (0\\.760)"))
   (should (lispm-mycin-test-wait-for "another ORGANISM\\? (y or n) "))
   (should-not (lispm-mycin-asking-p))
   (lispm-mycin-say "n")
   (lispm-mycin-test-answer "another CULTURE\\? (y or n) " "n")
   (lispm-mycin-test-answer "another PATIENT\\? (y or n) " "n")
   (should (lispm-mycin-test-wait-for "The consultation is over"))
   (should-not (lispm-mycin-running-p))))

(ert-deftest lispm-mycin-asking-why ()
  "Why, Answers and Unknown say MYCIN's words, and it asks on."
  (lispm-mycin-test-consultation
   (lispm-mycin-test-answer "Patient's name: " "Ada")
   (should (lispm-mycin-test-wait-for "Sex: "))
   (lispm-mycin-choices)
   (should (lispm-mycin-test-wait-for "A SEX must be of type (MEMBER MALE FEMALE)"))
   (should (lispm-mycin-test-wait-for "Sex: "))
   (lispm-mycin-why)
   (should (lispm-mycin-test-wait-for "Why is the value of SEX being asked for\\?"))
   (should (lispm-mycin-test-wait-for "Sex: "))
   (lispm-mycin-unknown)
   (should (lispm-mycin-test-wait-for "Age: "))
   (should (lispm-mycin-running-p))
   (should (equal (lispm-mycin-status) "Consulting"))))

(ert-deftest lispm-mycin-new-ends-the-old ()
  "A new consultation ends the one under way and starts afresh."
  (lispm-mycin-test-consultation
   (should (lispm-mycin-test-wait-for "Patient's name: "))
   (let ((old (get-buffer-process (current-buffer))))
     (lispm-mycin-new)
     (should-not (process-live-p old))
     (should (process-live-p (get-buffer-process (current-buffer))))
     (should-not (string-search "Patient's name" (buffer-string)))
     (set-marker lispm-mycin-test--from (point-min))
     (should (lispm-mycin-test-wait-for "Patient's name: ")))))

(ert-deftest lispm-mycin-knows-no-desktop ()
  "MYCIN stands alone: none of its files but the tests names LispM
Desktop's code, which dresses its window from its own side."
  (dolist (file (directory-files (file-name-directory (locate-library "lispm-mycin")) t "\\.el\\'"))
    (with-temp-buffer
      (insert-file-contents file)
      (should-not (and (re-search-forward "lispm-desktop\\|platinum" nil t)
                       (format "%s:%d" (file-name-nondirectory file) (line-number-at-pos)))))))

;;; lispm-mycin-test.el ends here
