;;;; trigger.lisp - Trigger definitions and operations
;;;;
;;;; SPDX-License-Identifier: MIT

(in-package #:cl-automation)

;;; ============================================================================
;;; Trigger Type Constants
;;; ============================================================================

(defconstant +trigger-type-time+ :time
  "Time-based trigger (cron or interval).")

(defconstant +trigger-type-event+ :event
  "Event-based trigger (contract event log).")

(defconstant +trigger-type-condition+ :condition
  "Condition-based trigger (contract state check).")

(defconstant +trigger-type-block+ :block
  "Block-based trigger (every N blocks).")

;;; ============================================================================
;;; Error Conditions
;;; ============================================================================

(define-condition trigger-error (automation-error)
  ((trigger-id :initarg :trigger-id
               :reader trigger-error-trigger-id
               :type (or null string)))
  (:default-initargs :code :trigger-error
                     :message "Trigger error")
  (:documentation "Error related to trigger operations."))

;;; ============================================================================
;;; Base Trigger Structure
;;; ============================================================================

(defstruct (trigger (:constructor %make-trigger)
                    (:copier nil)
                    (:predicate trigger-p))
  "Base trigger structure for automation.

   Slots:
   - id: Unique trigger identifier
   - type: Trigger type keyword
   - config: Type-specific configuration plist
   - enabled: Whether trigger is active
   - last-check: Timestamp of last evaluation
   - next-fire: Calculated next fire time
   - fire-count: Number of times trigger has fired"
  (id nil :type (or null string))
  (type :time :type keyword)
  (config nil :type list)
  (enabled t :type boolean)
  (last-check nil :type (or null integer))
  (next-fire nil :type (or null integer))
  (fire-count 0 :type (integer 0)))

;;; ============================================================================
;;; Time-Based Trigger
;;; ============================================================================

(defstruct (time-trigger (:include trigger)
                         (:constructor %make-time-trigger)
                         (:copier nil)
                         (:predicate time-trigger-p))
  "Time-based trigger using cron expression or fixed interval.

   Slots:
   - cron: Parsed cron schedule (or nil for interval-based)
   - interval: Interval in seconds (or nil for cron-based)
   - timezone: Timezone offset in seconds from UTC"
  (cron nil :type (or null cron-schedule))
  (interval nil :type (or null integer))
  (timezone 0 :type integer))

(defun make-time-trigger (&key id cron-expression interval (timezone 0) (enabled t))
  "Create a time-based trigger.

   Parameters:
   - id: Optional trigger ID (generated if not provided)
   - cron-expression: Cron expression string (e.g., '0 * * * *')
   - interval: Interval in seconds (alternative to cron)
   - timezone: Timezone offset from UTC in seconds
   - enabled: Whether trigger starts enabled

   Returns: time-trigger struct"
  (unless (or cron-expression interval)
    (error 'invalid-configuration
           :field :trigger
           :reason "Must provide either cron-expression or interval"))
  (let ((cron (when cron-expression
                (parse-cron-expression cron-expression)))
        (now (current-timestamp)))
    (%make-time-trigger
     :id (or id (generate-trigger-id))
     :type +trigger-type-time+
     :config (list :cron-expression cron-expression :interval interval)
     :enabled enabled
     :last-check now
     :next-fire (if cron
                    (calculate-next-fire cron now)
                    (+ now (or interval 60)))
     :cron cron
     :interval interval
     :timezone timezone)))

;;; ============================================================================
;;; Event-Based Trigger
;;; ============================================================================

(defstruct (event-trigger (:include trigger)
                          (:constructor %make-event-trigger)
                          (:copier nil)
                          (:predicate event-trigger-p))
  "Event-based trigger that fires on contract events.

   Slots:
   - contract: Contract address to monitor
   - event-signature: Event signature hash
   - filter-topics: Optional topic filters"
  (contract nil :type (or null string))
  (event-signature nil :type (or null string))
  (filter-topics nil :type list))

(defun make-event-trigger (&key id contract event-signature filter-topics (enabled t))
  "Create an event-based trigger.

   Parameters:
   - id: Optional trigger ID
   - contract: Contract address to monitor
   - event-signature: Event signature (e.g., 'Transfer(address,address,uint256)')
   - filter-topics: List of indexed parameter filters
   - enabled: Whether trigger starts enabled

   Returns: event-trigger struct"
  (unless contract
    (error 'invalid-configuration
           :field :contract
           :reason "Contract address required for event trigger"))
  (unless event-signature
    (error 'invalid-configuration
           :field :event-signature
           :reason "Event signature required"))
  (%make-event-trigger
   :id (or id (generate-trigger-id))
   :type +trigger-type-event+
   :config (list :contract contract
                 :event-signature event-signature
                 :filter-topics filter-topics)
   :enabled enabled
   :last-check (current-timestamp)
   :contract contract
   :event-signature event-signature
   :filter-topics filter-topics))

;;; ============================================================================
;;; Condition-Based Trigger
;;; ============================================================================

(defstruct (condition-trigger (:include trigger)
                              (:constructor %make-condition-trigger)
                              (:copier nil)
                              (:predicate condition-trigger-p))
  "Condition-based trigger that fires when contract state meets criteria.

   Slots:
   - contract: Contract address to check
   - method: View function to call
   - threshold: Value to compare against
   - comparison: Comparison operator (:gt :lt :eq :gte :lte)"
  (contract nil :type (or null string))
  (method nil :type (or null string))
  (threshold nil :type (or null number))
  (comparison :gt :type keyword))

(defun make-condition-trigger (&key id contract method threshold
                                    (comparison :gt) (enabled t))
  "Create a condition-based trigger.

   Parameters:
   - id: Optional trigger ID
   - contract: Contract address
   - method: View function name or signature
   - threshold: Numeric threshold
   - comparison: :gt, :lt, :eq, :gte, :lte
   - enabled: Whether trigger starts enabled

   Returns: condition-trigger struct"
  (unless contract
    (error 'invalid-configuration
           :field :contract
           :reason "Contract address required"))
  (unless method
    (error 'invalid-configuration
           :field :method
           :reason "Method required for condition trigger"))
  (%make-condition-trigger
   :id (or id (generate-trigger-id))
   :type +trigger-type-condition+
   :config (list :contract contract
                 :method method
                 :threshold threshold
                 :comparison comparison)
   :enabled enabled
   :last-check (current-timestamp)
   :contract contract
   :method method
   :threshold threshold
   :comparison comparison))

;;; ============================================================================
;;; Block-Based Trigger
;;; ============================================================================

(defstruct (block-trigger (:include trigger)
                          (:constructor %make-block-trigger)
                          (:copier nil)
                          (:predicate block-trigger-p))
  "Block-based trigger that fires every N blocks.

   Slots:
   - interval: Number of blocks between fires
   - start-block: Block number to start counting from
   - last-block: Last block number when fired"
  (interval 10 :type (integer 1))
  (start-block nil :type (or null integer))
  (last-block nil :type (or null integer)))

(defun make-block-trigger (&key id (interval 10) start-block (enabled t))
  "Create a block-based trigger.

   Parameters:
   - id: Optional trigger ID
   - interval: Blocks between fires (default: 10)
   - start-block: Optional starting block
   - enabled: Whether trigger starts enabled

   Returns: block-trigger struct"
  (when (< interval 1)
    (error 'invalid-configuration
           :field :interval
           :reason "Block interval must be at least 1"))
  (%make-block-trigger
   :id (or id (generate-trigger-id))
   :type +trigger-type-block+
   :config (list :interval interval :start-block start-block)
   :enabled enabled
   :last-check (current-timestamp)
   :interval interval
   :start-block start-block))

;;; ============================================================================
;;; Trigger Factory
;;; ============================================================================

(defun create-trigger (type &rest args)
  "Create a trigger of the specified TYPE.

   Parameters:
   - type: :time, :event, :condition, or :block
   - args: Type-specific keyword arguments

   Returns: Appropriate trigger struct"
  (ecase type
    (:time (apply #'make-time-trigger args))
    (:event (apply #'make-event-trigger args))
    (:condition (apply #'make-condition-trigger args))
    (:block (apply #'make-block-trigger args))))

;;; ============================================================================
;;; Trigger Operations
;;; ============================================================================

(defun enable-trigger (trigger)
  "Enable a trigger."
  (setf (trigger-enabled trigger) t)
  trigger)

(defun disable-trigger (trigger)
  "Disable a trigger."
  (setf (trigger-enabled trigger) nil)
  trigger)

(defun update-trigger (trigger &key enabled config)
  "Update trigger properties."
  (when enabled
    (setf (trigger-enabled trigger) enabled))
  (when config
    (setf (trigger-config trigger)
          (append config (trigger-config trigger))))
  trigger)

;;; ============================================================================
;;; Trigger Evaluation
;;; ============================================================================

(defgeneric check-trigger (trigger &key current-time current-block event-log)
  (:documentation "Check if a trigger should fire.

   Parameters:
   - trigger: Trigger to check
   - current-time: Current timestamp
   - current-block: Current block number
   - event-log: Recent event logs to check

   Returns: (values should-fire-p perform-data)"))

(defmethod check-trigger ((trigger time-trigger) &key (current-time (current-timestamp))
                                                      current-block event-log)
  "Check if time-based trigger should fire."
  (declare (ignore current-block event-log))
  (unless (trigger-enabled trigger)
    (return-from check-trigger (values nil nil)))

  (let ((next-fire (trigger-next-fire trigger)))
    (when (and next-fire (<= next-fire current-time))
      ;; Update next fire time
      (setf (trigger-next-fire trigger)
            (if (time-trigger-cron trigger)
                (calculate-next-fire (time-trigger-cron trigger) current-time)
                (+ current-time (or (time-trigger-interval trigger) 60))))
      (setf (trigger-last-check trigger) current-time)
      (incf (trigger-fire-count trigger))
      (values t nil))))

(defmethod check-trigger ((trigger event-trigger) &key current-time current-block event-log)
  "Check if event-based trigger should fire."
  (declare (ignore current-block))
  (unless (trigger-enabled trigger)
    (return-from check-trigger (values nil nil)))

  (setf (trigger-last-check trigger) (or current-time (current-timestamp)))

  ;; Check event log for matching events
  (let ((contract (event-trigger-contract trigger))
        (signature (event-trigger-event-signature trigger))
        (filters (event-trigger-filter-topics trigger)))
    (dolist (event event-log)
      (when (and (equal (getf event :address) contract)
                 (equal (getf event :topic0) signature)
                 (or (null filters)
                     (every (lambda (f)
                              (or (null (car f))
                                  (equal (getf event (cdr f)) (car f))))
                            filters)))
        (incf (trigger-fire-count trigger))
        (return-from check-trigger (values t event)))))
  (values nil nil))

(defmethod check-trigger ((trigger condition-trigger) &key current-time current-block event-log
                                                           contract-value)
  "Check if condition-based trigger should fire.
   CONTRACT-VALUE should be provided by the caller after querying the chain."
  (declare (ignore current-block event-log))
  (unless (trigger-enabled trigger)
    (return-from check-trigger (values nil nil)))

  (setf (trigger-last-check trigger) (or current-time (current-timestamp)))

  (when contract-value
    (let ((threshold (condition-trigger-threshold trigger))
          (comparison (condition-trigger-comparison trigger)))
      (when (and threshold
                 (ecase comparison
                   (:gt (> contract-value threshold))
                   (:lt (< contract-value threshold))
                   (:eq (= contract-value threshold))
                   (:gte (>= contract-value threshold))
                   (:lte (<= contract-value threshold))))
        (incf (trigger-fire-count trigger))
        (return-from check-trigger (values t (list :value contract-value))))))
  (values nil nil))

(defmethod check-trigger ((trigger block-trigger) &key current-time current-block event-log)
  "Check if block-based trigger should fire."
  (declare (ignore event-log))
  (unless (trigger-enabled trigger)
    (return-from check-trigger (values nil nil)))

  (setf (trigger-last-check trigger) (or current-time (current-timestamp)))

  (when current-block
    (let ((interval (block-trigger-interval trigger))
          (start (or (block-trigger-start-block trigger) 0))
          (last-block (block-trigger-last-block trigger)))
      (when (and (>= current-block start)
                 (or (null last-block)
                     (>= (- current-block last-block) interval)))
        (setf (block-trigger-last-block trigger) current-block)
        (incf (trigger-fire-count trigger))
        (return-from check-trigger (values t (list :block current-block))))))
  (values nil nil))

(defun evaluate-trigger (trigger &rest args)
  "Evaluate a trigger and return whether it should fire.
   Alias for check-trigger."
  (apply #'check-trigger trigger args))

;;; ============================================================================
;;; Trigger Registry
;;; ============================================================================

(defvar *trigger-registry* (make-hash-table :test #'equal)
  "Global registry of all triggers.")

(defun get-trigger (trigger-id)
  "Get a trigger by ID from the registry."
  (gethash trigger-id *trigger-registry*))

(defun list-triggers (&key type enabled-only)
  "List all registered triggers, optionally filtered."
  (let ((results nil))
    (maphash (lambda (id trigger)
               (declare (ignore id))
               (when (and (or (null type)
                              (eq (trigger-type trigger) type))
                          (or (not enabled-only)
                              (trigger-enabled trigger)))
                 (push trigger results)))
             *trigger-registry*)
    (nreverse results)))

(defun register-trigger (trigger)
  "Register a trigger in the global registry."
  (setf (gethash (trigger-id trigger) *trigger-registry*) trigger)
  trigger)

(defun unregister-trigger (trigger-id)
  "Remove a trigger from the registry."
  (remhash trigger-id *trigger-registry*))

(defun delete-trigger (trigger-or-id)
  "Delete a trigger from the registry."
  (let ((id (if (stringp trigger-or-id)
                trigger-or-id
                (trigger-id trigger-or-id))))
    (unregister-trigger id)))
