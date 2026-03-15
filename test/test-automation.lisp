;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;; SPDX-License-Identifier: Apache-2.0

;;;; test-automation.lisp - Tests for cl-automation
;;;;
;;;; SPDX-License-Identifier: MIT

(in-package #:cl-automation.test)

;;; ============================================================================
;;; Test Infrastructure
;;; ============================================================================

(defvar *test-count* 0)
(defvar *pass-count* 0)
(defvar *fail-count* 0)

(defmacro deftest (name &body body)
  "Define a test case."
  `(defun ,name ()
     (incf *test-count*)
     (handler-case
         (progn
           ,@body
           (incf *pass-count*)
           (format t "~&  PASS: ~A~%" ',name)
           t)
       (error (e)
         (incf *fail-count*)
         (format t "~&  FAIL: ~A~%        ~A~%" ',name e)
         nil))))

(defmacro assert-true (form &optional message)
  "Assert that FORM evaluates to true."
  `(unless ,form
     (error "Assertion failed~@[: ~A~]" ,message)))

(defmacro assert-false (form &optional message)
  "Assert that FORM evaluates to false."
  `(when ,form
     (error "Expected false~@[: ~A~]" ,message)))

(defmacro assert-equal (expected actual &optional message)
  "Assert that EXPECTED equals ACTUAL."
  `(unless (equal ,expected ,actual)
     (error "Expected ~S but got ~S~@[: ~A~]" ,expected ,actual ,message)))

(defmacro assert-error (condition &body body)
  "Assert that BODY signals a condition of type CONDITION."
  `(handler-case
       (progn ,@body
              (error "Expected error ~A but none signaled" ',condition))
     (,condition () t)
     (error (e)
       (error "Expected ~A but got ~A" ',condition (type-of e)))))

;;; ============================================================================
;;; Utility Tests
;;; ============================================================================

(deftest test-generate-id
  (let ((id1 (cl-automation::generate-id "TST"))
        (id2 (cl-automation::generate-id "TST")))
    (assert-true (stringp id1))
    (assert-true (stringp id2))
    (assert-true (not (string= id1 id2)) "IDs should be unique")))

(deftest test-cron-parser
  (let ((schedule (cl-automation::parse-cron-expression "0 * * * *")))
    (assert-true (cl-automation::cron-schedule-p schedule))
    (assert-equal '(0) (cl-automation::cron-schedule-minute schedule))))

(deftest test-cron-parser-range
  (let ((schedule (cl-automation::parse-cron-expression "0-5 * * * *")))
    (assert-equal '(0 1 2 3 4 5) (cl-automation::cron-schedule-minute schedule))))

(deftest test-cron-parser-step
  (let ((schedule (cl-automation::parse-cron-expression "*/15 * * * *")))
    (assert-equal '(0 15 30 45) (cl-automation::cron-schedule-minute schedule))))

(deftest test-priority-queue
  (let ((pq (cl-automation::make-priority-queue)))
    (assert-true (cl-automation::pq-empty-p pq))
    (cl-automation::pq-push pq :a 3)
    (cl-automation::pq-push pq :b 1)
    (cl-automation::pq-push pq :c 2)
    (assert-equal 3 (cl-automation::pq-size pq))
    (assert-equal :b (cl-automation::pq-pop pq))
    (assert-equal :c (cl-automation::pq-pop pq))
    (assert-equal :a (cl-automation::pq-pop pq))
    (assert-true (cl-automation::pq-empty-p pq))))

;;; ============================================================================
;;; Trigger Tests
;;; ============================================================================

(deftest test-time-trigger-interval
  (let ((trigger (make-time-trigger :interval 60)))
    (assert-true (time-trigger-p trigger))
    (assert-equal :time (trigger-type trigger))
    (assert-equal 60 (time-trigger-interval trigger))
    (assert-true (trigger-enabled trigger))))

(deftest test-time-trigger-cron
  (let ((trigger (make-time-trigger :cron-expression "0 * * * *")))
    (assert-true (time-trigger-p trigger))
    (assert-true (time-trigger-cron trigger))
    (assert-true (trigger-next-fire trigger))))

(deftest test-event-trigger
  (let ((trigger (make-event-trigger
                  :contract "0x1234567890abcdef"
                  :event-signature "Transfer(address,address,uint256)")))
    (assert-true (event-trigger-p trigger))
    (assert-equal :event (trigger-type trigger))
    (assert-equal "0x1234567890abcdef" (event-trigger-contract trigger))))

(deftest test-condition-trigger
  (let ((trigger (make-condition-trigger
                  :contract "0xabcdef1234567890"
                  :method "balanceOf"
                  :threshold 1000
                  :comparison :gt)))
    (assert-true (condition-trigger-p trigger))
    (assert-equal :condition (trigger-type trigger))
    (assert-equal :gt (condition-trigger-comparison trigger))))

(deftest test-block-trigger
  (let ((trigger (make-block-trigger :interval 10)))
    (assert-true (block-trigger-p trigger))
    (assert-equal :block (trigger-type trigger))
    (assert-equal 10 (block-trigger-interval trigger))))

(deftest test-trigger-enable-disable
  (let ((trigger (make-time-trigger :interval 60)))
    (assert-true (trigger-enabled trigger))
    (disable-trigger trigger)
    (assert-false (trigger-enabled trigger))
    (enable-trigger trigger)
    (assert-true (trigger-enabled trigger))))

(deftest test-trigger-factory
  (let ((time (create-trigger :time :interval 60))
        (event (create-trigger :event
                               :contract "0x123"
                               :event-signature "Event()"))
        (cond (create-trigger :condition
                              :contract "0x456"
                              :method "check"
                              :threshold 100))
        (block (create-trigger :block :interval 5)))
    (assert-true (time-trigger-p time))
    (assert-true (event-trigger-p event))
    (assert-true (condition-trigger-p cond))
    (assert-true (block-trigger-p block))))

;;; ============================================================================
;;; Scheduler Tests
;;; ============================================================================

(deftest test-scheduler-creation
  (let ((sched (make-scheduler)))
    (assert-true (scheduler-p sched))
    (assert-false (scheduler-running sched))
    (assert-true (hash-table-p (scheduler-upkeeps sched)))))

(deftest test-upkeep-registration
  (let ((sched (make-scheduler)))
    (let ((upkeep (register-upkeep sched
                                    "Test Upkeep"
                                    "0xowner"
                                    "0xtarget"
                                    500000
                                    1000000)))
      (assert-true (upkeep-p upkeep))
      (assert-equal "Test Upkeep" (upkeep-name upkeep))
      (assert-equal "0xowner" (upkeep-owner upkeep))
      (assert-equal :active (upkeep-status upkeep)))))

(deftest test-upkeep-time-registration
  (let ((sched (make-scheduler)))
    (let ((upkeep (register-time-upkeep sched
                                         "Hourly Task"
                                         "0xowner"
                                         "0xtarget"
                                         300000
                                         500000
                                         :cron-expression "0 * * * *")))
      (assert-true (upkeep-p upkeep))
      (assert-true (upkeep-trigger upkeep))
      (assert-equal :time (upkeep-trigger-type upkeep)))))

(deftest test-upkeep-funding
  (let ((sched (make-scheduler)))
    (let ((upkeep (register-upkeep sched "Test" "0xowner" "0xtarget" 500000 1000)))
      (assert-equal 1000 (get-balance sched (upkeep-id upkeep)))
      (add-funds sched (upkeep-id upkeep) 500)
      (assert-equal 1500 (get-balance sched (upkeep-id upkeep)))
      (withdraw-funds sched (upkeep-id upkeep) 200 "0xowner")
      (assert-equal 1300 (get-balance sched (upkeep-id upkeep))))))

(deftest test-upkeep-insufficient-funds
  (let ((sched (make-scheduler)))
    (let ((upkeep (register-upkeep sched "Test" "0xowner" "0xtarget" 500000 100)))
      (assert-error insufficient-funds
        (withdraw-funds sched (upkeep-id upkeep) 1000 "0xowner")))))

(deftest test-upkeep-pause-unpause
  (let ((sched (make-scheduler)))
    (let ((upkeep (register-upkeep sched "Test" "0xowner" "0xtarget" 500000 1000
                                    :admin "0xadmin")))
      (assert-equal :active (upkeep-status upkeep))
      (pause-upkeep sched (upkeep-id upkeep) "0xadmin")
      (assert-equal :paused (upkeep-status upkeep))
      (assert-true (upkeep-paused-p sched (upkeep-id upkeep)))
      (unpause-upkeep sched (upkeep-id upkeep) "0xadmin")
      (assert-equal :active (upkeep-status upkeep)))))

(deftest test-upkeep-cancel
  (let ((sched (make-scheduler)))
    (let ((upkeep (register-upkeep sched "Test" "0xowner" "0xtarget" 500000 1000)))
      (let ((remaining (cancel-upkeep sched (upkeep-id upkeep) "0xowner")))
        (assert-equal 1000 remaining)
        (assert-equal :cancelled (upkeep-status upkeep))
        (assert-equal 0 (upkeep-balance upkeep))))))

(deftest test-upkeep-unauthorized
  (let ((sched (make-scheduler)))
    (let ((upkeep (register-upkeep sched "Test" "0xowner" "0xtarget" 500000 1000
                                    :admin "0xadmin")))
      (assert-error unauthorized-access
        (pause-upkeep sched (upkeep-id upkeep) "0xwrongadmin")))))

(deftest test-scheduler-stats
  (let ((sched (make-scheduler)))
    (register-upkeep sched "Test1" "0xowner1" "0xtarget" 500000 1000)
    (register-upkeep sched "Test2" "0xowner2" "0xtarget" 500000 2000)
    (let ((stats (get-statistics sched)))
      (assert-equal 2 (getf stats :total-upkeeps))
      (assert-equal 2 (getf stats :active-upkeeps)))))

;;; ============================================================================
;;; Executor Tests
;;; ============================================================================

(deftest test-executor-creation
  (let ((exec (make-executor :max-concurrent 5)))
    (assert-true (executor-p exec))
    (assert-equal :idle (executor-status exec))
    (assert-equal 5 (executor-max-concurrent exec))))

(deftest test-executor-start-stop
  (let ((exec (make-executor)))
    (assert-equal :idle (executor-status exec))
    (start-executor exec)
    (assert-equal :running (executor-status exec))
    (stop-executor exec)
    (assert-equal :stopped (executor-status exec))))

(deftest test-execution-record
  (let ((exec (make-executor))
        (sched (make-scheduler)))
    (start-executor exec)
    (let* ((upkeep (register-upkeep sched "Test" "0xowner" "0xtarget"
                                     500000 10000000))
           (execution (execute-upkeep exec upkeep)))
      (assert-true (execution-p execution))
      (assert-equal (upkeep-id upkeep) (execution-upkeep-id execution))
      (assert-equal +execution-success+ (execution-status execution)))))

(deftest test-executor-stats
  (let ((exec (make-executor))
        (sched (make-scheduler)))
    (start-executor exec)
    (let ((upkeep (register-upkeep sched "Test" "0xowner" "0xtarget"
                                    500000 10000000)))
      (execute-upkeep exec upkeep)
      (execute-upkeep exec upkeep)
      (let ((stats (get-executor-stats exec)))
        (assert-equal :running (getf stats :status))
        (assert-equal 2 (getf stats :total-executions))))))

;;; ============================================================================
;;; Integration Tests
;;; ============================================================================

(deftest test-global-initialization
  (multiple-value-bind (sched exec)
      (initialize-automation)
    (assert-true (scheduler-p sched))
    (assert-true (executor-p exec))
    (assert-equal *default-scheduler* sched)
    (assert-equal *default-executor* exec)
    (shutdown-automation)
    (assert-true (null *default-scheduler*))
    (assert-true (null *default-executor*))))

;;; ============================================================================
;;; Test Runner
;;; ============================================================================

(defun run-tests ()
  "Run all tests and report results."
  (setf *test-count* 0
        *pass-count* 0
        *fail-count* 0)

  (format t "~&=== cl-automation Test Suite ===~%~%")

  (format t "~&Utility Tests:~%")
  (test-generate-id)
  (test-cron-parser)
  (test-cron-parser-range)
  (test-cron-parser-step)
  (test-priority-queue)

  (format t "~&~%Trigger Tests:~%")
  (test-time-trigger-interval)
  (test-time-trigger-cron)
  (test-event-trigger)
  (test-condition-trigger)
  (test-block-trigger)
  (test-trigger-enable-disable)
  (test-trigger-factory)

  (format t "~&~%Scheduler Tests:~%")
  (test-scheduler-creation)
  (test-upkeep-registration)
  (test-upkeep-time-registration)
  (test-upkeep-funding)
  (test-upkeep-insufficient-funds)
  (test-upkeep-pause-unpause)
  (test-upkeep-cancel)
  (test-upkeep-unauthorized)
  (test-scheduler-stats)

  (format t "~&~%Executor Tests:~%")
  (test-executor-creation)
  (test-executor-start-stop)
  (test-execution-record)
  (test-executor-stats)

  (format t "~&~%Integration Tests:~%")
  (test-global-initialization)

  (format t "~&~%=== Results ===~%")
  (format t "Total: ~D  Passed: ~D  Failed: ~D~%"
          *test-count* *pass-count* *fail-count*)

  (if (zerop *fail-count*)
      (format t "~&All tests passed!~%")
      (format t "~&~D test(s) FAILED~%" *fail-count*))

  (zerop *fail-count*))
