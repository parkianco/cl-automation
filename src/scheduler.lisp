;;;; scheduler.lisp - Execution scheduler for automation triggers
;;;;
;;;; SPDX-License-Identifier: MIT

(in-package #:cl-automation)

;;; ============================================================================
;;; Upkeep Structure
;;; ============================================================================

(defstruct (upkeep (:constructor %make-upkeep)
                   (:copier nil)
                   (:predicate upkeep-p))
  "Represents an automated upkeep task.

   Slots:
   - id: Unique upkeep identifier
   - name: Human-readable name
   - owner: Address of the upkeep owner
   - target: Target contract address
   - check-data: Data passed to check function
   - perform-data: Data passed to perform function
   - gas-limit: Maximum gas allowed
   - balance: Current funding balance
   - min-balance: Minimum required balance
   - status: Current status (:active, :paused, :cancelled)
   - last-performed: Timestamp of last execution
   - total-performs: Count of successful executions
   - total-gas-used: Cumulative gas used
   - created-at: Creation timestamp
   - updated-at: Last update timestamp
   - admin: Admin address
   - trigger: Associated trigger object
   - trigger-type: Type of trigger"
  (id nil :type (or null string))
  (name nil :type (or null string))
  (owner nil :type (or null string))
  (target nil :type (or null string))
  (check-data nil :type (or null vector))
  (perform-data nil :type (or null vector))
  (gas-limit 500000 :type (integer 21000))
  (balance 0 :type (integer 0))
  (min-balance 0 :type (integer 0))
  (status :active :type keyword)
  (last-performed nil :type (or null integer))
  (total-performs 0 :type (integer 0))
  (total-gas-used 0 :type (integer 0))
  (created-at 0 :type integer)
  (updated-at 0 :type integer)
  (admin nil :type (or null string))
  (trigger nil :type (or null trigger))
  (trigger-type :time :type keyword))

;;; ============================================================================
;;; Scheduler Structure
;;; ============================================================================

(defstruct (scheduler (:constructor %make-scheduler)
                      (:copier nil)
                      (:predicate scheduler-p))
  "Execution scheduler managing upkeep tasks.

   Slots:
   - id: Unique scheduler identifier
   - running: Whether scheduler is running
   - upkeeps: Hash table of upkeep-id -> upkeep
   - pending-queue: Priority queue of pending executions
   - config: Scheduler configuration plist
   - lock: Mutex for thread safety
   - thread: Background scheduler thread"
  (id nil :type (or null string))
  (running nil :type boolean)
  (upkeeps nil :type (or null hash-table))
  (pending-queue nil :type (or null priority-queue))
  (config nil :type list)
  (lock nil :type (or null sb-thread:mutex))
  (thread nil :type (or null sb-thread:thread)))

(defun make-scheduler (&key id config)
  "Create a new scheduler.

   Parameters:
   - id: Optional scheduler ID
   - config: Configuration plist

   Returns: scheduler struct"
  (%make-scheduler
   :id (or id (generate-scheduler-id))
   :running nil
   :upkeeps (make-hash-table :test #'equal)
   :pending-queue (make-priority-queue :compare #'<)
   :config (or config
               (list :check-interval 1
                     :max-pending 1000
                     :min-upkeep-balance 0
                     :max-gas-price 1000000000000))
   :lock (sb-thread:make-mutex :name "scheduler-lock")))

;;; ============================================================================
;;; Default Scheduler
;;; ============================================================================

(defvar *default-scheduler* nil
  "Default global scheduler instance.")

;;; ============================================================================
;;; Upkeep Registration
;;; ============================================================================

(defun register-upkeep (scheduler name owner target gas-limit initial-funding
                        &key check-data perform-data admin trigger)
  "Register a new upkeep with the scheduler.

   Parameters:
   - scheduler: The scheduler
   - name: Upkeep name
   - owner: Owner address
   - target: Target contract address
   - gas-limit: Maximum gas
   - initial-funding: Initial balance
   - check-data: Optional check data
   - perform-data: Optional perform data
   - admin: Optional admin address
   - trigger: Trigger object

   Returns: New upkeep"
  (let* ((now (current-timestamp))
         (upkeep (%make-upkeep
                  :id (generate-upkeep-id)
                  :name name
                  :owner owner
                  :target target
                  :check-data check-data
                  :perform-data perform-data
                  :gas-limit gas-limit
                  :balance initial-funding
                  :min-balance (calculate-min-balance-internal scheduler gas-limit)
                  :status :active
                  :created-at now
                  :updated-at now
                  :admin (or admin owner)
                  :trigger trigger
                  :trigger-type (if trigger (trigger-type trigger) :time))))

    (sb-thread:with-mutex ((scheduler-lock scheduler))
      (setf (gethash (upkeep-id upkeep) (scheduler-upkeeps scheduler)) upkeep)
      ;; Schedule initial check
      (when trigger
        (schedule-upkeep-internal scheduler upkeep)))

    upkeep))

(defun register-time-upkeep (scheduler name owner target gas-limit initial-funding
                             &key cron-expression interval admin)
  "Register a time-based upkeep.

   Parameters:
   - scheduler: The scheduler
   - name: Upkeep name
   - owner: Owner address
   - target: Target contract
   - gas-limit: Max gas
   - initial-funding: Initial balance
   - cron-expression: Cron expression (e.g., '0 * * * *')
   - interval: Interval in seconds (alternative to cron)
   - admin: Optional admin

   Returns: New upkeep"
  (let ((trigger (make-time-trigger
                  :cron-expression cron-expression
                  :interval interval)))
    (register-upkeep scheduler name owner target gas-limit initial-funding
                     :admin admin
                     :trigger trigger)))

(defun register-event-upkeep (scheduler name owner target gas-limit initial-funding
                              &key contract event-signature filter-topics admin)
  "Register an event-based upkeep.

   Parameters:
   - scheduler: The scheduler
   - name: Upkeep name
   - owner: Owner address
   - target: Target contract to call
   - gas-limit: Max gas
   - initial-funding: Initial balance
   - contract: Contract to monitor for events
   - event-signature: Event signature
   - filter-topics: Optional topic filters
   - admin: Optional admin

   Returns: New upkeep"
  (let ((trigger (make-event-trigger
                  :contract contract
                  :event-signature event-signature
                  :filter-topics filter-topics)))
    (register-upkeep scheduler name owner target gas-limit initial-funding
                     :admin admin
                     :trigger trigger)))

(defun register-condition-upkeep (scheduler name owner target gas-limit initial-funding
                                  &key contract method threshold comparison admin)
  "Register a condition-based upkeep.

   Parameters:
   - scheduler: The scheduler
   - name: Upkeep name
   - owner: Owner address
   - target: Target contract
   - gas-limit: Max gas
   - initial-funding: Initial balance
   - contract: Contract to check
   - method: View method to call
   - threshold: Threshold value
   - comparison: Comparison operator
   - admin: Optional admin

   Returns: New upkeep"
  (let ((trigger (make-condition-trigger
                  :contract contract
                  :method method
                  :threshold threshold
                  :comparison (or comparison :gt))))
    (register-upkeep scheduler name owner target gas-limit initial-funding
                     :admin admin
                     :trigger trigger)))

;;; ============================================================================
;;; Upkeep Operations
;;; ============================================================================

(defun update-upkeep (scheduler upkeep-id &key name gas-limit check-data perform-data)
  "Update an existing upkeep."
  (let ((upkeep (get-upkeep scheduler upkeep-id)))
    (unless upkeep
      (error 'upkeep-not-found :upkeep-id upkeep-id))
    (sb-thread:with-mutex ((scheduler-lock scheduler))
      (when name (setf (upkeep-name upkeep) name))
      (when gas-limit
        (setf (upkeep-gas-limit upkeep) gas-limit)
        (setf (upkeep-min-balance upkeep)
              (calculate-min-balance-internal scheduler gas-limit)))
      (when check-data (setf (upkeep-check-data upkeep) check-data))
      (when perform-data (setf (upkeep-perform-data upkeep) perform-data))
      (setf (upkeep-updated-at upkeep) (current-timestamp)))
    upkeep))

(defun cancel-upkeep (scheduler upkeep-id owner)
  "Cancel an upkeep and return remaining balance."
  (let ((upkeep (get-upkeep scheduler upkeep-id)))
    (unless upkeep
      (error 'upkeep-not-found :upkeep-id upkeep-id))
    (unless (string= owner (upkeep-owner upkeep))
      (error 'unauthorized-access :actor owner :action :cancel))

    (let ((remaining (upkeep-balance upkeep)))
      (sb-thread:with-mutex ((scheduler-lock scheduler))
        (setf (upkeep-status upkeep) :cancelled)
        (setf (upkeep-balance upkeep) 0)
        (setf (upkeep-updated-at upkeep) (current-timestamp))
        ;; Remove from pending queue
        (pq-remove-if (scheduler-pending-queue scheduler)
                      (lambda (item) (string= (upkeep-id item) upkeep-id))))
      remaining)))

(defun pause-upkeep (scheduler upkeep-id admin)
  "Pause an upkeep."
  (let ((upkeep (get-upkeep scheduler upkeep-id)))
    (unless upkeep
      (error 'upkeep-not-found :upkeep-id upkeep-id))
    (unless (string= admin (upkeep-admin upkeep))
      (error 'unauthorized-access :actor admin :action :pause))

    (sb-thread:with-mutex ((scheduler-lock scheduler))
      (setf (upkeep-status upkeep) :paused)
      (setf (upkeep-updated-at upkeep) (current-timestamp)))
    upkeep))

(defun unpause-upkeep (scheduler upkeep-id admin)
  "Unpause an upkeep."
  (let ((upkeep (get-upkeep scheduler upkeep-id)))
    (unless upkeep
      (error 'upkeep-not-found :upkeep-id upkeep-id))
    (unless (string= admin (upkeep-admin upkeep))
      (error 'unauthorized-access :actor admin :action :unpause))
    (unless (eq (upkeep-status upkeep) :paused)
      (error 'automation-error :code :invalid-state
                               :message "Upkeep is not paused"))

    (sb-thread:with-mutex ((scheduler-lock scheduler))
      (setf (upkeep-status upkeep) :active)
      (setf (upkeep-updated-at upkeep) (current-timestamp))
      (schedule-upkeep-internal scheduler upkeep))
    upkeep))

;;; ============================================================================
;;; Funding Operations
;;; ============================================================================

(defun add-funds (scheduler upkeep-id amount)
  "Add funds to an upkeep."
  (let ((upkeep (get-upkeep scheduler upkeep-id)))
    (unless upkeep
      (error 'upkeep-not-found :upkeep-id upkeep-id))
    (sb-thread:with-mutex ((scheduler-lock scheduler))
      (incf (upkeep-balance upkeep) amount)
      (setf (upkeep-updated-at upkeep) (current-timestamp)))
    (upkeep-balance upkeep)))

(defun withdraw-funds (scheduler upkeep-id amount owner)
  "Withdraw funds from an upkeep."
  (let ((upkeep (get-upkeep scheduler upkeep-id)))
    (unless upkeep
      (error 'upkeep-not-found :upkeep-id upkeep-id))
    (unless (string= owner (upkeep-owner upkeep))
      (error 'unauthorized-access :actor owner :action :withdraw))
    (when (> amount (upkeep-balance upkeep))
      (error 'insufficient-funds
             :upkeep-id upkeep-id
             :required amount
             :available (upkeep-balance upkeep)))

    (sb-thread:with-mutex ((scheduler-lock scheduler))
      (decf (upkeep-balance upkeep) amount)
      (setf (upkeep-updated-at upkeep) (current-timestamp)))
    amount))

(defun get-balance (scheduler upkeep-id)
  "Get current balance of an upkeep."
  (let ((upkeep (get-upkeep scheduler upkeep-id)))
    (when upkeep
      (upkeep-balance upkeep))))

(defun get-min-balance (scheduler upkeep-id)
  "Get minimum required balance for an upkeep."
  (let ((upkeep (get-upkeep scheduler upkeep-id)))
    (when upkeep
      (upkeep-min-balance upkeep))))

(defun calculate-min-balance-internal (scheduler gas-limit)
  "Calculate minimum balance for given gas limit."
  (let ((gas-price (or (getf (scheduler-config scheduler) :max-gas-price)
                       1000000000)))
    (* gas-limit gas-price)))

(defun estimate-cost (scheduler gas-limit &optional (executions 1))
  "Estimate cost for executions."
  (* executions (calculate-min-balance-internal scheduler gas-limit)))

;;; ============================================================================
;;; Query Operations
;;; ============================================================================

(defun get-upkeep (scheduler upkeep-id)
  "Get an upkeep by ID."
  (gethash upkeep-id (scheduler-upkeeps scheduler)))

(defun get-upkeep-info (scheduler upkeep-id)
  "Get comprehensive info about an upkeep."
  (let ((upkeep (get-upkeep scheduler upkeep-id)))
    (when upkeep
      (list :id (upkeep-id upkeep)
            :name (upkeep-name upkeep)
            :owner (upkeep-owner upkeep)
            :admin (upkeep-admin upkeep)
            :target (upkeep-target upkeep)
            :gas-limit (upkeep-gas-limit upkeep)
            :balance (upkeep-balance upkeep)
            :min-balance (upkeep-min-balance upkeep)
            :status (upkeep-status upkeep)
            :trigger-type (upkeep-trigger-type upkeep)
            :last-performed (upkeep-last-performed upkeep)
            :total-performs (upkeep-total-performs upkeep)
            :total-gas-used (upkeep-total-gas-used upkeep)
            :created-at (upkeep-created-at upkeep)))))

(defun get-upkeeps-by-owner (scheduler owner &key status (limit 100))
  "Get upkeeps owned by an address."
  (let ((results nil) (count 0))
    (maphash (lambda (id upkeep)
               (declare (ignore id))
               (when (and (< count limit)
                          (string= (upkeep-owner upkeep) owner)
                          (or (null status)
                              (eq (upkeep-status upkeep) status)))
                 (push upkeep results)
                 (incf count)))
             (scheduler-upkeeps scheduler))
    (nreverse results)))

(defun get-upkeeps-by-status (scheduler status &key (limit 100))
  "Get upkeeps with a specific status."
  (let ((results nil) (count 0))
    (maphash (lambda (id upkeep)
               (declare (ignore id))
               (when (and (< count limit)
                          (eq (upkeep-status upkeep) status))
                 (push upkeep results)
                 (incf count)))
             (scheduler-upkeeps scheduler))
    (nreverse results)))

(defun get-active-upkeeps (scheduler &key (limit 100))
  "Get all active upkeeps."
  (get-upkeeps-by-status scheduler :active :limit limit))

(defun upkeep-paused-p (scheduler upkeep-id)
  "Check if an upkeep is paused."
  (let ((upkeep (get-upkeep scheduler upkeep-id)))
    (and upkeep (eq (upkeep-status upkeep) :paused))))

;;; ============================================================================
;;; Scheduling Operations
;;; ============================================================================

(defun schedule-upkeep (scheduler upkeep)
  "Schedule an upkeep for execution."
  (sb-thread:with-mutex ((scheduler-lock scheduler))
    (schedule-upkeep-internal scheduler upkeep)))

(defun schedule-upkeep-internal (scheduler upkeep)
  "Internal scheduling (assumes lock held)."
  (let ((trigger (upkeep-trigger upkeep)))
    (when (and trigger (trigger-enabled trigger))
      (let ((next-time (or (trigger-next-fire trigger)
                           (+ (current-timestamp) 60))))
        (pq-push (scheduler-pending-queue scheduler) upkeep next-time)))))

(defun unschedule-upkeep (scheduler upkeep-id)
  "Remove an upkeep from the schedule."
  (sb-thread:with-mutex ((scheduler-lock scheduler))
    (pq-remove-if (scheduler-pending-queue scheduler)
                  (lambda (u) (string= (upkeep-id u) upkeep-id)))))

(defun reschedule-upkeep (scheduler upkeep)
  "Reschedule an upkeep after execution."
  (let ((trigger (upkeep-trigger upkeep)))
    (when trigger
      (schedule-upkeep-internal scheduler upkeep))))

(defun get-next-execution (scheduler)
  "Get the next scheduled execution time."
  (pq-peek-priority (scheduler-pending-queue scheduler)))

(defun get-pending-executions (scheduler &key (limit 10))
  "Get list of pending executions."
  (let ((results nil)
        (queue (scheduler-pending-queue scheduler)))
    (loop for i from 0 below limit
          for item = (nth i (priority-queue-items queue))
          while item
          do (push (cons (car item) (cdr item)) results))
    (nreverse results)))

;;; ============================================================================
;;; Scheduler Control
;;; ============================================================================

(defun start-scheduler (scheduler &key executor)
  "Start the scheduler background thread.

   Parameters:
   - scheduler: The scheduler
   - executor: Executor to use for running upkeeps

   Returns: scheduler"
  (when (scheduler-running scheduler)
    (return-from start-scheduler scheduler))

  (setf (scheduler-running scheduler) t)
  (setf (scheduler-thread scheduler)
        (sb-thread:make-thread
         (lambda () (scheduler-loop scheduler executor))
         :name (format nil "scheduler-~A" (scheduler-id scheduler))))
  scheduler)

(defun stop-scheduler (scheduler)
  "Stop the scheduler background thread."
  (setf (scheduler-running scheduler) nil)
  (when (scheduler-thread scheduler)
    ;; Give thread time to notice running=nil
    (sleep 0.1)
    (when (sb-thread:thread-alive-p (scheduler-thread scheduler))
      (sb-thread:terminate-thread (scheduler-thread scheduler)))
    (setf (scheduler-thread scheduler) nil))
  scheduler)

(defun scheduler-running-p (scheduler)
  "Check if scheduler is running."
  (scheduler-running scheduler))

(defun scheduler-loop (scheduler executor)
  "Main scheduler loop."
  (let ((check-interval (or (getf (scheduler-config scheduler) :check-interval) 1)))
    (loop while (scheduler-running scheduler)
          do (handler-case
                 (process-pending-upkeeps scheduler executor)
               (error (e)
                 (format *error-output* "Scheduler error: ~A~%" e)))
             (sleep check-interval))))

(defun process-pending-upkeeps (scheduler executor)
  "Process upkeeps that are due for execution."
  (let ((now (current-timestamp)))
    (loop
      (let ((next-time (pq-peek-priority (scheduler-pending-queue scheduler))))
        (when (or (null next-time) (> next-time now))
          (return))

        (let ((upkeep (sb-thread:with-mutex ((scheduler-lock scheduler))
                        (pq-pop (scheduler-pending-queue scheduler)))))
          (when upkeep
            ;; Check if upkeep is still active and funded
            (when (and (eq (upkeep-status upkeep) :active)
                       (>= (upkeep-balance upkeep) (upkeep-min-balance upkeep)))
              ;; Check trigger
              (let ((trigger (upkeep-trigger upkeep)))
                (when trigger
                  (multiple-value-bind (should-fire perform-data)
                      (check-trigger trigger :current-time now)
                    (when should-fire
                      ;; Execute if executor provided
                      (when executor
                        (execute-upkeep executor upkeep :perform-data perform-data)))))))

            ;; Reschedule
            (sb-thread:with-mutex ((scheduler-lock scheduler))
              (reschedule-upkeep scheduler upkeep))))))))

;;; ============================================================================
;;; Statistics
;;; ============================================================================

(defun get-scheduler-stats (scheduler)
  "Get scheduler statistics."
  (let ((total 0) (active 0) (paused 0) (cancelled 0)
        (total-performs 0) (total-gas 0))
    (maphash (lambda (id upkeep)
               (declare (ignore id))
               (incf total)
               (ecase (upkeep-status upkeep)
                 (:active (incf active))
                 (:paused (incf paused))
                 (:cancelled (incf cancelled)))
               (incf total-performs (upkeep-total-performs upkeep))
               (incf total-gas (upkeep-total-gas-used upkeep)))
             (scheduler-upkeeps scheduler))
    (list :total-upkeeps total
          :active-upkeeps active
          :paused-upkeeps paused
          :cancelled-upkeeps cancelled
          :total-performs total-performs
          :total-gas-used total-gas
          :pending-count (pq-size (scheduler-pending-queue scheduler)))))

(defun get-statistics (scheduler)
  "Alias for get-scheduler-stats."
  (get-scheduler-stats scheduler))

(defun get-upkeep-statistics (scheduler upkeep-id)
  "Get statistics for a specific upkeep."
  (let ((upkeep (get-upkeep scheduler upkeep-id)))
    (when upkeep
      (list :id (upkeep-id upkeep)
            :total-performs (upkeep-total-performs upkeep)
            :total-gas-used (upkeep-total-gas-used upkeep)
            :last-performed (upkeep-last-performed upkeep)
            :balance (upkeep-balance upkeep)
            :status (upkeep-status upkeep)))))
