;;;; cl-automation.asd - Smart Contract Automation Triggers
;;;;
;;;; SPDX-License-Identifier: MIT
;;;; Copyright (c) 2024-2026 CLPIC Development Team

(asdf:defsystem "cl-automation"
  :description "Standalone smart contract automation triggers for Common Lisp"
  :author "CLPIC Development Team"
  :license "MIT"
  :version "1.0.0"
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
  :in-order-to ((test-op (test-op "cl-automation/test"))))

(asdf:defsystem "cl-automation/test"
  :description "Tests for cl-automation"
  :depends-on ("cl-automation")
  :serial t
  :components
  ((:module "test"
    :components
    ((:file "test-automation"))))
  :perform (test-op (o c)
             (symbol-call :cl-automation.test :run-tests)))
