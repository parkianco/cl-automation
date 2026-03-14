;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;; SPDX-License-Identifier: BSD-3-Clause

;;;; cl-automation.asd - Smart Contract Automation Triggers
;;;;
;;;; SPDX-License-Identifier: MIT
;;;; Copyright (c) 2024-2026 Parkian Company LLC

(asdf:defsystem "cl-automation"
  :description "Standalone smart contract automation triggers for Common Lisp"
  :author "Parkian Company LLC"
  :license "MIT"
  :version "0.1.0"
  :depends-on ()
  :serial t
  :components
  ((:file "package")
   (:module "src"
    :serial t
    :components
    ((:file "util")
     (:file "trigger")
     (:file "scheduler")
     (:file "executor"))))
  :in-order-to ((asdf:test-op (test-op "cl-automation/test"))))

(asdf:defsystem "cl-automation/test"
  :description "Tests for cl-automation"
  :depends-on ("cl-automation")
  :serial t
  :components
  ((:module "test"
    :components
    ((:file "test-automation"))))
  :perform (asdf:test-op (o c)
             (let ((result (uiop:symbol-call :cl-automation.test :run-tests)))
               (unless result
                 (error "Tests failed")))))
