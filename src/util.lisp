;;;; util.lisp - Utility functions for cl-automation
;;;;
;;;; SPDX-License-Identifier: MIT

(in-package #:cl-automation)

;;; ============================================================================
;;; Thread Safety
;;; ============================================================================

(defvar *automation-lock* (sb-thread:make-mutex :name "cl-automation-lock")
  "Global mutex for thread-safe operations.")

(defmacro with-automation-lock (&body body)
  "Execute BODY with the automation lock held."
  `(sb-thread:with-mutex (*automation-lock*)
     ,@body))

;;; ============================================================================
;;; ID Generation
;;; ============================================================================

(defvar *id-counter* 0
  "Counter for generating unique IDs.")

(defun generate-id (prefix)
  "Generate a unique ID with the given PREFIX."
  (format nil "~A-~8,'0D-~4,'0X"
          prefix
          (with-automation-lock
            (incf *id-counter*))
          (random #xFFFF)))

(defun generate-upkeep-id ()
  "Generate a unique upkeep ID."
  (generate-id "UPK"))

(defun generate-trigger-id ()
  "Generate a unique trigger ID."
  (generate-id "TRG"))

(defun generate-execution-id ()
  "Generate a unique execution ID."
  (generate-id "EXE"))

(defun generate-scheduler-id ()
  "Generate a unique scheduler ID."
  (generate-id "SCH"))

(defun generate-executor-id ()
  "Generate a unique executor ID."
  (generate-id "EXC"))

;;; ============================================================================
;;; Time Utilities
;;; ============================================================================

(defun current-timestamp ()
  "Return current Unix timestamp."
  (get-universal-time))

(defun timestamp-to-string (timestamp)
  "Convert TIMESTAMP to human-readable string."
  (multiple-value-bind (sec min hour day month year)
      (decode-universal-time timestamp)
    (format nil "~4,'0D-~2,'0D-~2,'0D ~2,'0D:~2,'0D:~2,'0D"
            year month day hour min sec)))

(defun seconds-until (timestamp)
  "Return seconds until TIMESTAMP from now."
  (max 0 (- timestamp (current-timestamp))))

(defun add-seconds (timestamp seconds)
  "Add SECONDS to TIMESTAMP."
  (+ timestamp seconds))

;;; ============================================================================
;;; Cron Expression Parser
;;; ============================================================================

(defstruct (cron-schedule (:constructor %make-cron-schedule))
  "Parsed cron expression.
   Supports: minute hour day-of-month month day-of-week"
  (minute nil :type list)      ; 0-59
  (hour nil :type list)        ; 0-23
  (day-of-month nil :type list) ; 1-31
  (month nil :type list)       ; 1-12
  (day-of-week nil :type list)) ; 0-6 (0=Sunday)

(defun parse-cron-field (field min-val max-val)
  "Parse a single cron field into a list of valid values."
  (cond
    ;; Wildcard
    ((string= field "*")
     (loop for i from min-val to max-val collect i))
    ;; Range (e.g., "1-5")
    ((find #\- field)
     (let* ((parts (split-string field #\-))
            (start (parse-integer (first parts)))
            (end (parse-integer (second parts))))
       (loop for i from start to end collect i)))
    ;; Step (e.g., "*/5")
    ((and (> (length field) 2) (char= (char field 0) #\*) (char= (char field 1) #\/))
     (let ((step (parse-integer (subseq field 2))))
       (loop for i from min-val to max-val by step collect i)))
    ;; List (e.g., "1,3,5")
    ((find #\, field)
     (mapcar #'parse-integer (split-string field #\,)))
    ;; Single value
    (t
     (list (parse-integer field)))))

(defun split-string (string delimiter)
  "Split STRING by DELIMITER character."
  (loop for start = 0 then (1+ pos)
        for pos = (position delimiter string :start start)
        collect (subseq string start (or pos (length string)))
        while pos))

(defun parse-cron-expression (expression)
  "Parse a cron expression string into a cron-schedule.
   Format: 'minute hour day-of-month month day-of-week'"
  (let ((fields (split-string expression #\Space)))
    (unless (= (length fields) 5)
      (error 'invalid-configuration
             :field :cron-expression
             :reason "Cron expression must have 5 fields"))
    (%make-cron-schedule
     :minute (parse-cron-field (nth 0 fields) 0 59)
     :hour (parse-cron-field (nth 1 fields) 0 23)
     :day-of-month (parse-cron-field (nth 2 fields) 1 31)
     :month (parse-cron-field (nth 3 fields) 1 12)
     :day-of-week (parse-cron-field (nth 4 fields) 0 6))))

(defun validate-cron-expression (expression)
  "Validate a cron expression, returning T if valid or signaling error."
  (handler-case
      (progn
        (parse-cron-expression expression)
        t)
    (error (e)
      (declare (ignore e))
      nil)))

(defun calculate-next-fire (schedule &optional (from (current-timestamp)))
  "Calculate the next fire time for a cron SCHEDULE after FROM timestamp."
  (multiple-value-bind (sec min hour day month year dow)
      (decode-universal-time from)
    (declare (ignore sec dow))
    ;; Simple implementation: check each minute for the next 365 days
    (loop for minute-offset from 1 to (* 365 24 60)
          for check-time = (add-seconds from (* minute-offset 60))
          do (multiple-value-bind (csec cmin chour cday cmonth cyear cdow)
                 (decode-universal-time check-time)
               (declare (ignore csec cyear))
               (when (and (member cmin (cron-schedule-minute schedule))
                          (member chour (cron-schedule-hour schedule))
                          (member cday (cron-schedule-day-of-month schedule))
                          (member cmonth (cron-schedule-month schedule))
                          (member cdow (cron-schedule-day-of-week schedule)))
                 (return check-time)))
          finally (return nil))))

;;; ============================================================================
;;; Validation Helpers
;;; ============================================================================

(defun valid-address-p (address)
  "Check if ADDRESS looks like a valid address (hex string)."
  (and (stringp address)
       (>= (length address) 10)
       (every (lambda (c) (or (digit-char-p c)
                              (find c "abcdefABCDEF")))
              (if (and (> (length address) 2)
                       (string= "0x" (subseq address 0 2)))
                  (subseq address 2)
                  address))))

(defun valid-gas-limit-p (gas-limit)
  "Check if GAS-LIMIT is valid."
  (and (integerp gas-limit)
       (>= gas-limit 21000)
       (<= gas-limit 30000000)))

;;; ============================================================================
;;; Priority Queue (for Scheduler)
;;; ============================================================================

(defstruct (priority-queue (:constructor %make-priority-queue))
  "Simple priority queue using a sorted list."
  (items nil :type list)
  (compare #'< :type function))

(defun make-priority-queue (&key (compare #'<))
  "Create a new priority queue with COMPARE function for ordering."
  (%make-priority-queue :compare compare))

(defun pq-empty-p (pq)
  "Return T if priority queue PQ is empty."
  (null (priority-queue-items pq)))

(defun pq-size (pq)
  "Return number of items in priority queue PQ."
  (length (priority-queue-items pq)))

(defun pq-push (pq item priority)
  "Push ITEM with PRIORITY into priority queue PQ."
  (let ((entry (cons priority item))
        (compare (priority-queue-compare pq)))
    (setf (priority-queue-items pq)
          (merge 'list (list entry) (priority-queue-items pq)
                 (lambda (a b) (funcall compare (car a) (car b)))))))

(defun pq-pop (pq)
  "Pop and return the highest priority item from PQ."
  (when (priority-queue-items pq)
    (let ((entry (pop (priority-queue-items pq))))
      (cdr entry))))

(defun pq-peek (pq)
  "Return the highest priority item without removing it."
  (when (priority-queue-items pq)
    (cdr (first (priority-queue-items pq)))))

(defun pq-peek-priority (pq)
  "Return the priority of the highest priority item."
  (when (priority-queue-items pq)
    (car (first (priority-queue-items pq)))))

(defun pq-remove-if (pq predicate)
  "Remove all items matching PREDICATE from PQ."
  (setf (priority-queue-items pq)
        (remove-if (lambda (entry) (funcall predicate (cdr entry)))
                   (priority-queue-items pq))))
