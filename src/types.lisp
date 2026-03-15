;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;; SPDX-License-Identifier: Apache-2.0

(in-package #:cl-automation)

;;; Core types for cl-automation
(deftype cl-automation-id () '(unsigned-byte 64))
(deftype cl-automation-status () '(member :ready :active :error :shutdown))
