;;;; mycin.lisp --- Loaded after PAIP's MYCIN.
;;;;
;;;; Copyright (C) 2026  Ryan.K
;;;; SPDX-License-Identifier: AGPL-3.0-or-later
;;;;
;;;; An answer MYCIN cannot read, as (male .5, female .5), would end the
;;;; consultation: the rest of its line is dropped and the question asked
;;;; again.  The end of the input still ends it.

(let ((ask (symbol-function 'prompt-and-read-vals)))
  (setf (symbol-function 'prompt-and-read-vals)
        (lambda (parm inst)
          (loop
            (handler-case (return (funcall ask parm inst))
              (end-of-file (condition) (error condition))
              (error (condition)
                (clear-input)
                (format t "~&MYCIN cannot read that answer: ~A.  ~
                           Type ? for the answers it takes.~%"
                        (string-right-trim
                         "." (el:|emacs-cl-inferior--describe| condition)))))))))
