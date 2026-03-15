;;;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;;;; SPDX-License-Identifier: Apache-2.0

;;;; package.lisp - cl-automation package definitions
;;;;
;;;; SPDX-License-Identifier: MIT

(defpackage #:cl-automation
  (:use #:cl)
  (:documentation
   "Smart contract automation triggers for Common Lisp.

    This library provides:
    - Multiple trigger types (time-based, event-based, condition-based)
    - Upkeep registration and lifecycle management
    - Execution scheduling with priority queues
    - Funding management for automated tasks
    - Admin controls with role-based access
    - Statistics and monitoring

    Designed for automated on-chain task execution (Chainlink Automation style).")

  ;; =========================================================================
  ;; Error Conditions
  ;; =========================================================================
  (:export
   #:automation-error
   #:automation-error-code
   #:automation-error-message
   #:upkeep-not-found
   #:upkeep-not-found-id
   #:insufficient-funds
   #:insufficient-funds-upkeep-id
   #:insufficient-funds-required
   #:insufficient-funds-available
   #:upkeep-paused
   #:upkeep-paused-upkeep-id
   #:unauthorized-access
   #:unauthorized-access-actor
   #:unauthorized-access-action
   #:invalid-configuration
   #:invalid-configuration-field
   #:invalid-configuration-reason
   #:trigger-error
   #:trigger-error-trigger-id
   #:execution-error
   #:execution-error-job-id)

  ;; =========================================================================
  ;; Trigger Types
  ;; =========================================================================
  (:export
   ;; Base trigger
   #:trigger
   #:make-trigger
   #:trigger-p
   #:trigger-id
   #:trigger-type
   #:trigger-config
   #:trigger-enabled
   #:trigger-last-check
   #:trigger-next-fire
   #:trigger-fire-count

   ;; Time-based trigger
   #:time-trigger
   #:make-time-trigger
   #:time-trigger-p
   #:time-trigger-cron
   #:time-trigger-interval
   #:time-trigger-timezone

   ;; Event-based trigger
   #:event-trigger
   #:make-event-trigger
   #:event-trigger-p
   #:event-trigger-contract
   #:event-trigger-event-signature
   #:event-trigger-filter-topics

   ;; Condition-based trigger
   #:condition-trigger
   #:make-condition-trigger
   #:condition-trigger-p
   #:condition-trigger-contract
   #:condition-trigger-method
   #:condition-trigger-threshold
   #:condition-trigger-comparison

   ;; Block-based trigger
   #:block-trigger
   #:make-block-trigger
   #:block-trigger-p
   #:block-trigger-interval
   #:block-trigger-start-block

   ;; Trigger type constants
   #:+trigger-type-time+
   #:+trigger-type-event+
   #:+trigger-type-condition+
   #:+trigger-type-block+)

  ;; =========================================================================
  ;; Trigger Operations
  ;; =========================================================================
  (:export
   #:create-trigger
   #:update-trigger
   #:delete-trigger
   #:enable-trigger
   #:disable-trigger
   #:check-trigger
   #:evaluate-trigger
   #:get-trigger
   #:list-triggers

   ;; Cron utilities
   #:parse-cron-expression
   #:calculate-next-fire
   #:validate-cron-expression)

  ;; =========================================================================
  ;; Upkeep Structure
  ;; =========================================================================
  (:export
   #:upkeep
   #:make-upkeep
   #:upkeep-p
   #:upkeep-id
   #:upkeep-name
   #:upkeep-owner
   #:upkeep-target
   #:upkeep-check-data
   #:upkeep-perform-data
   #:upkeep-gas-limit
   #:upkeep-balance
   #:upkeep-min-balance
   #:upkeep-status
   #:upkeep-last-performed
   #:upkeep-total-performs
   #:upkeep-total-gas-used
   #:upkeep-created-at
   #:upkeep-updated-at
   #:upkeep-admin
   #:upkeep-trigger
   #:upkeep-trigger-type)

  ;; =========================================================================
  ;; Scheduler Structure
  ;; =========================================================================
  (:export
   #:scheduler
   #:make-scheduler
   #:scheduler-p
   #:scheduler-id
   #:scheduler-running
   #:scheduler-upkeeps
   #:scheduler-pending-queue
   #:scheduler-config

   ;; Scheduler operations
   #:start-scheduler
   #:stop-scheduler
   #:scheduler-running-p
   #:schedule-upkeep
   #:unschedule-upkeep
   #:reschedule-upkeep
   #:get-next-execution
   #:get-pending-executions
   #:get-scheduler-stats)

  ;; =========================================================================
  ;; Executor Structure
  ;; =========================================================================
  (:export
   #:executor
   #:make-executor
   #:executor-p
   #:executor-id
   #:executor-status
   #:executor-max-concurrent
   #:executor-active-jobs

   ;; Execution record
   #:execution
   #:make-execution
   #:execution-p
   #:execution-id
   #:execution-upkeep-id
   #:execution-trigger-id
   #:execution-status
   #:execution-started-at
   #:execution-completed-at
   #:execution-gas-used
   #:execution-result
   #:execution-error

   ;; Executor operations
   #:start-executor
   #:stop-executor
   #:execute-upkeep
   #:cancel-execution
   #:get-execution
   #:get-executions
   #:get-executor-stats

   ;; Execution status constants
   #:+execution-pending+
   #:+execution-running+
   #:+execution-success+
   #:+execution-failed+
   #:+execution-cancelled+)

  ;; =========================================================================
  ;; Registry (Integration)
  ;; =========================================================================
  (:export
   ;; Upkeep registration
   #:register-upkeep
   #:register-time-upkeep
   #:register-event-upkeep
   #:register-condition-upkeep
   #:update-upkeep
   #:cancel-upkeep
   #:pause-upkeep
   #:unpause-upkeep

   ;; Funding
   #:add-funds
   #:withdraw-funds
   #:get-balance
   #:get-min-balance
   #:estimate-cost

   ;; Queries
   #:get-upkeep
   #:get-upkeep-info
   #:get-upkeeps-by-owner
   #:get-upkeeps-by-status
   #:get-active-upkeeps
   #:upkeep-paused-p

   ;; Statistics
   #:get-statistics
   #:get-upkeep-statistics)

  ;; =========================================================================
  ;; Global State
  ;; =========================================================================
  (:export
   #:*default-scheduler*
   #:*default-executor*
   #:initialize-automation
   #:shutdown-automation))

(defpackage #:cl-automation.test
  (:use #:cl #:cl-automation)
  (:export #:run-tests))
