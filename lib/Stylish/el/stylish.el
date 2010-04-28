;;; stylish.el --- talk to a stylish server

;; Copyright (C) 2010  Jonathan Rockway

;; Author: Jonathan Rockway <jon@jrock.us>
;; Keywords:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:

(require 'cl)
(require 'json)

(defvar stylish-outstanding-request-handlers nil
  "Alist of cookie -> (handler . args) representing handlers for Stylish requests")

(defvar stylish-next-cookie 1
  "Cookie to be used for the next request")

(defvar stylish-partial-message "")

(defvar stylish-process nil)

(defun stylish-get-next-cookie ()
  "Return a unique cookie for the next request."
  (prog1 stylish-next-cookie (incf stylish-next-cookie)))

(defun stylish-filter (process message)
  "Tend to the Stylish connection.
Argument PROCESS is the stylish process.
Argument MESSAGE is the text we got from stylish."
  (setf stylish-partial-message (concat stylish-partial-message message))
  (stylish-process-buffer))

(defun stylish-sentinel (&rest args)
  "Tend to the Stylish connection.
Optional argument ARGS blah.")

(defun stylish-connect ()
  "Connect to a stylish Stylish server."
  (interactive)
  (when stylish-process
    (delete-process stylish-process)
    (setf stylish-partial-message nil)) ;; also kill?
  (setf stylish-process
        (make-network-process :name "stylish"
                              :family 'local
                              :service "/tmp/stylish"
                              :noquery t
                              :filter #'stylish-filter
                              :sentinel #'stylish-sentinel
                              :coding 'utf-8)))

(defun stylish (&optional reconnect)
  "Connect to Stylish, if not already connected.
Prefix argument RECONNECT forces a reconnect."
  (interactive "p")
  (when (or (not stylish-process) (eq reconnect 4))
    (stylish-connect)))

(defun stylish-process-buffer ()
  (while (and (not (null stylish-partial-message))
              (string-match "^\\(.+\\)\n\\(.*\\)$" stylish-partial-message))
    (let ((message (match-string 1 stylish-partial-message)))
      (condition-case e
          (stylish-process-message (stylish-json-decode message))
          (error (message "Error processing stylish message '%s': %s" message e)))
      (setf stylish-partial-message (match-string 2 stylish-partial-message)))))

(defun stylish-json-decode (string)
  (let ((json-object-type 'plist)
        (json-array-type 'list))
    (json-read-from-string string)))

(defun stylish-process-message (message)
  "Process the Stylish response represented MESSAGE."
  (let* ((cookie  (parse-integer (getf message :cookie)))
         (command (getf message :command))
         (result  (getf message :result))
         (error   (getf message :error)))
    (cond ((not (null cookie))
           (let* ((handler-row (cdr (assq cookie stylish-outstanding-request-handlers)))
                  (closure (nth 0 handler-row))
                  (handler (or (nth 1 handler-row)
                               (lambda (&rest args)
                                 (message "stylish: unhandled message: %s %s %s %s"
                                          cookie command result args))))
                  (error-handler (or (nth 2 handler-row)
                                     (lambda (&rest args)
                                       (message "stylish: error: %s" error))))
                  (handler-result
                   (if error
                       (funcall error-handler error closure)
                     (funcall handler command result closure))))
             (when (not (eq handler-result :keep-handler))
               (setf stylish-outstanding-request-handlers
                     (assq-delete-all cookie stylish-outstanding-request-handlers)))))
          ((equal command "welcome")
           ;; a hat tip to SLIME ;)
           (message "Connected. Let the hacking begin.")))))

(defun stylish-message-encode (command cookie args)
  "Encode a message for transmission over the wire.
Argument COMMAND is the command to run.
Argument COOKIE is the unique cookie identifying this query.
Argument ARGS are the args for the command, a plist."
  (json-encode (append (list :cookie cookie :command command) args)))

(defun stylish-send-message (command &optional args callback error-callback closure)
  "Send COMMAND with ARGS to the stylish server, and call CALLBACK with CLOSURE when the command is finished.  Call ERROR-CALLBACK on error."
  (let* ((cookie (stylish-get-next-cookie))
         (message (stylish-message-encode command cookie args)))
    (setf stylish-outstanding-request-handlers
          (cons (list cookie closure callback error-callback)
                stylish-outstanding-request-handlers))
    (process-send-string stylish-process (concat message "\n"))))

(provide 'stylish)
;;; stylish.el ends here
