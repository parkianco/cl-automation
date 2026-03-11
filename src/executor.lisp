;;;; executor.lisp - Trigger execution engine
;;;;
;;;; SPDX-License-Identifier: MIT

(in-package #:cl-automation)

;;; ============================================================================
;;; Execution Status Constants
;;; ============================================================================

(defconstant +execution-pending+ :pending
  "Execution is waiting to start.")

(defconstant +execution-running+ :running
  "Execution is in progress.")

(defconstant +execution-success+ :success
  "Execution completed successfully.")

(defconstant +execution-failed+ :failed
  "Execution failed with error.")

(defconstant +execution-cancelled+ :cancelled
  "Execution was cancelled.")

;;; ============================================================================
;;; Error Conditions
;;; ============================================================================

(define-condition execution-error (automation-error)
  ((job-id :initarg :job-id
           :reader execution-error-job-id
           :type (or null string)))
  (:default-initargs :code :execution-error
                     :message "Execution error")
  (:documentation "Error during upkeep execution."))

;;; ============================================================================
;;; Execution Record
;;; ============================================================================

(defstruct (execution (:constructor %make-execution)
                      (:copier nil)
                      (:predicate execution-p))
  "Record of an upkeep execution.

   Slots:
   - id: Unique execution identifier
   - upkeep-id: Associated upkeep ID
   - trigger-id: Trigger that caused execution
   - status: Current status
   - started-at: Start timestamp
   - completed-at: Completion timestamp
   - gas-used: Gas consumed
   - result: Execution result data
   - error: Error message if failed"
  (id nil :type (or null string))
  (upkeep-id nil :type (or null string))
  (trigger-id nil :type (or null string))
  (status :pending :type keyword)
  (started-at nil :type (or null integer))
  (completed-at nil :type (or null integer))
  (gas-used 0 :type (integer 0))
  (result nil :type t)
  (error nil :type (or null string)))

;;; ============================================================================
;;; Executor Structure
;;; ============================================================================

(defstruct (executor (:constructor %make-executor)
                     (:copier nil)
                     (:predicate executor-p))
  "Execution engine for running upkeep tasks.

   Slots:
   - id: Unique executor identifier
   - status: Current status (:idle, :running, :stopped)
   - max-concurrent: Maximum concurrent executions
   - active-jobs: Currently running jobs
   - execution-history: List of past executions
   - execute-fn: Function to call for actual execution
   - config: Configuration plist
   - lock: Mutex for thread safety"
  (id nil :type (or null string))
  (status :idle :type keyword)
  (max-concurrent 10 :type (integer 1))
  (active-jobs nil :type list)
  (execution-history nil :type list)
  (execute-fn nil :type (or null function))
  (config nil :type list)
  (lock nil :type (or null sb-thread:mutex)))

(defun make-executor (&key id (max-concurrent 10) execute-fn config)
  "Create a new executor.

   Parameters:
   - id: Optional executor ID
   - max-concurrent: Max concurrent executions
   - execute-fn: Function (upkeep perform-data) -> result
   - config: Configuration plist

   Returns: executor struct"
  (%make-executor
   :id (or id (generate-executor-id))
   :status :idle
   :max-concurrent max-concurrent
   :execute-fn execute-fn
   :config (or config (list :timeout 60
                            :retry-count 0
                            :max-history 1000))
   :lock (sb-thread:make-mutex :name "executor-lock")))

;;; ============================================================================
;;; Default Executor
;;; ============================================================================

(defvar *default-executor* nil
  "Default global executor instance.")

;;; ============================================================================
;;; Executor Control
;;; ============================================================================

(defun start-executor (executor)
  "Start the executor."
  (setf (executor-status executor) :running)
  executor)

(defun stop-executor (executor)
  "Stop the executor."
  (setf (executor-status executor) :stopped)
  executor)

;;; ============================================================================
;;; Execution Operations
;;; ============================================================================

(defun execute-upkeep (executor upkeep &key perform-data)
  "Execute an upkeep task.

   Parameters:
   - executor: The executor
   - upkeep: Upkeep to execute
   - perform-data: Data for the perform call

   Returns: execution record"
  (unless (eq (executor-status executor) :running)
    (error 'execution-error
           :job-id (upkeep-id upkeep)
           :code :executor-stopped
           :message "Executor is not running"))

  (when (>= (length (executor-active-jobs executor))
            (executor-max-concurrent executor))
    (error 'execution-error
           :job-id (upkeep-id upkeep)
           :code :max-concurrent
           :message "Maximum concurrent executions reached"))

  (let* ((now (current-timestamp))
         (execution (%make-execution
                     :id (generate-execution-id)
                     :upkeep-id (upkeep-id upkeep)
                     :trigger-id (when (upkeep-trigger upkeep)
                                   (trigger-id (upkeep-trigger upkeep)))
                     :status +execution-pending+
                     :started-at now)))

    ;; Add to active jobs
    (sb-thread:with-mutex ((executor-lock executor))
      (push execution (executor-active-jobs executor)))

    ;; Execute
    (setf (execution-status execution) +execution-running+)

    (handler-case
        (let ((result (if (executor-execute-fn executor)
                          (funcall (executor-execute-fn executor)
                                   upkeep perform-data)
                          ;; Default: simulate execution
                          (simulate-execution upkeep perform-data))))
          ;; Success
          (setf (execution-status execution) +execution-success+)
          (setf (execution-result execution) result)
          (setf (execution-completed-at execution) (current-timestamp))

          ;; Simulate gas usage
          (let ((gas (floor (upkeep-gas-limit upkeep) 2)))
            (setf (execution-gas-used execution) gas)

            ;; Update upkeep
            (incf (upkeep-total-performs upkeep))
            (incf (upkeep-total-gas-used upkeep) gas)
            (setf (upkeep-last-performed upkeep) (current-timestamp))

            ;; Deduct from balance
            (decf (upkeep-balance upkeep) gas)))

      (error (e)
        ;; Failure
        (setf (execution-status execution) +execution-failed+)
        (setf (execution-error execution) (format nil "~A" e))
        (setf (execution-completed-at execution) (current-timestamp))))

    ;; Move to history
    (sb-thread:with-mutex ((executor-lock executor))
      (setf (executor-active-jobs executor)
            (remove execution (executor-active-jobs executor)))
      (push execution (executor-execution-history executor))
      ;; Trim history
      (let ((max-history (or (getf (executor-config executor) :max-history) 1000)))
        (when (> (length (executor-execution-history executor)) max-history)
          (setf (executor-execution-history executor)
                (subseq (executor-execution-history executor) 0 max-history)))))

    execution))

(defun simulate-execution (upkeep perform-data)
  "Simulate execution for testing/demo purposes."
  (declare (ignore perform-data))
  (list :simulated t
        :upkeep-id (upkeep-id upkeep)
        :target (upkeep-target upkeep)
        :timestamp (current-timestamp)))

(defun cancel-execution (executor execution-id)
  "Cancel a pending or running execution."
  (sb-thread:with-mutex ((executor-lock executor))
    (let ((execution (find execution-id (executor-active-jobs executor)
                           :key #'execution-id
                           :test #'string=)))
      (when execution
        (setf (execution-status execution) +execution-cancelled+)
        (setf (execution-completed-at execution) (current-timestamp))
        (setf (executor-active-jobs executor)
              (remove execution (executor-active-jobs executor)))
        (push execution (executor-execution-history executor)))
      execution)))

;;; ============================================================================
;;; Query Operations
;;; ============================================================================

(defun get-execution (executor execution-id)
  "Get an execution by ID."
  (or (find execution-id (executor-active-jobs executor)
            :key #'execution-id :test #'string=)
      (find execution-id (executor-execution-history executor)
            :key #'execution-id :test #'string=)))

(defun get-executions (executor &key upkeep-id status (limit 100))
  "Get executions, optionally filtered."
  (let ((results nil)
        (count 0)
        (all-executions (append (executor-active-jobs executor)
                                (executor-execution-history executor))))
    (dolist (exec all-executions)
      (when (>= count limit)
        (return))
      (when (and (or (null upkeep-id)
                     (string= (execution-upkeep-id exec) upkeep-id))
                 (or (null status)
                     (eq (execution-status exec) status)))
        (push exec results)
        (incf count)))
    (nreverse results)))

(defun get-executor-stats (executor)
  "Get executor statistics."
  (let ((history (executor-execution-history executor))
        (success-count 0)
        (failed-count 0)
        (total-gas 0))
    (dolist (exec history)
      (ecase (execution-status exec)
        ((:success) (incf success-count))
        ((:failed :cancelled) (incf failed-count))
        ((:pending :running) nil))
      (incf total-gas (execution-gas-used exec)))
    (list :status (executor-status executor)
          :active-jobs (length (executor-active-jobs executor))
          :max-concurrent (executor-max-concurrent executor)
          :total-executions (length history)
          :successful-executions success-count
          :failed-executions failed-count
          :total-gas-used total-gas)))

;;; ============================================================================
;;; Global Initialization
;;; ============================================================================

(defun initialize-automation (&key scheduler-config executor-config execute-fn)
  "Initialize the global automation system.

   Parameters:
   - scheduler-config: Configuration for scheduler
   - executor-config: Configuration for executor
   - execute-fn: Function for actual execution

   Returns: (values scheduler executor)"
  (setf *default-scheduler* (make-scheduler :config scheduler-config))
  (setf *default-executor* (make-executor :config executor-config
                                          :execute-fn execute-fn))
  (start-executor *default-executor*)
  (start-scheduler *default-scheduler* :executor *default-executor*)
  (values *default-scheduler* *default-executor*))

(defun shutdown-automation ()
  "Shutdown the global automation system."
  (when *default-scheduler*
    (stop-scheduler *default-scheduler*)
    (setf *default-scheduler* nil))
  (when *default-executor*
    (stop-executor *default-executor*)
    (setf *default-executor* nil))
  t)
