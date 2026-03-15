;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;; SPDX-License-Identifier: Apache-2.0

(in-package #:cl-automation)

(define-condition cl-automation-error (error)
  ((message :initarg :message :reader cl-automation-error-message))
  (:report (lambda (condition stream)
             (format stream "cl-automation error: ~A" (cl-automation-error-message condition)))))
