# cl-automation

Smart contract automation triggers for Common Lisp.

Provides Chainlink Automation-style functionality for scheduling and executing automated on-chain tasks.

## Features

- **Multiple trigger types**: Time-based (cron/interval), event-based, condition-based, block-based
- **Upkeep management**: Registration, funding, pause/unpause, cancellation
- **Execution scheduler**: Priority queue with configurable concurrency
- **Thread-safe**: All operations protected by mutexes
- **Zero dependencies**: Pure Common Lisp with SBCL extensions

## Installation

```lisp
;; Load the system
(asdf:load-system :cl-automation)
```

## Quick Start

```lisp
(use-package :cl-automation)

;; Initialize the automation system
(initialize-automation)

;; Register a time-based upkeep (runs every hour)
(register-time-upkeep *default-scheduler*
                      "Hourly Maintenance"
                      "0xowner-address"
                      "0xtarget-contract"
                      500000      ; gas limit
                      10000000    ; initial funding
                      :cron-expression "0 * * * *")

;; Register an event-based upkeep
(register-event-upkeep *default-scheduler*
                       "On Transfer"
                       "0xowner"
                       "0xhandler-contract"
                       300000
                       5000000
                       :contract "0xtoken-contract"
                       :event-signature "Transfer(address,address,uint256)")

;; Register a condition-based upkeep
(register-condition-upkeep *default-scheduler*
                           "Rebalance When Needed"
                           "0xowner"
                           "0xrebalancer"
                           1000000
                           20000000
                           :contract "0xpool"
                           :method "imbalanceRatio"
                           :threshold 110
                           :comparison :gt)

;; Shutdown when done
(shutdown-automation)
```

## Trigger Types

### Time-Based Triggers

Execute on a schedule using cron expressions or fixed intervals.

```lisp
;; Cron expression (every hour at minute 0)
(make-time-trigger :cron-expression "0 * * * *")

;; Fixed interval (every 5 minutes = 300 seconds)
(make-time-trigger :interval 300)
```

Cron format: `minute hour day-of-month month day-of-week`

### Event-Based Triggers

Execute when specific contract events are emitted.

```lisp
(make-event-trigger
  :contract "0x1234..."
  :event-signature "Transfer(address,address,uint256)"
  :filter-topics '((:topic1 . value1)))  ; optional filters
```

### Condition-Based Triggers

Execute when a contract state meets certain criteria.

```lisp
(make-condition-trigger
  :contract "0xabcd..."
  :method "balanceOf"
  :threshold 1000000
  :comparison :lt)  ; :gt :lt :eq :gte :lte
```

### Block-Based Triggers

Execute every N blocks.

```lisp
(make-block-trigger :interval 10)
```

## API Reference

### Upkeep Registration

- `register-upkeep` - Register a generic upkeep
- `register-time-upkeep` - Register with time trigger
- `register-event-upkeep` - Register with event trigger
- `register-condition-upkeep` - Register with condition trigger

### Upkeep Operations

- `update-upkeep` - Update upkeep properties
- `pause-upkeep` - Pause an upkeep
- `unpause-upkeep` - Resume a paused upkeep
- `cancel-upkeep` - Cancel and reclaim funds

### Funding

- `add-funds` - Add funds to an upkeep
- `withdraw-funds` - Withdraw funds
- `get-balance` - Check current balance
- `estimate-cost` - Estimate execution costs

### Queries

- `get-upkeep` - Get upkeep by ID
- `get-upkeep-info` - Get detailed upkeep info
- `get-upkeeps-by-owner` - List owner's upkeeps
- `get-active-upkeeps` - List all active upkeeps
- `get-statistics` - Get scheduler statistics

### Global Functions

- `initialize-automation` - Initialize scheduler and executor
- `shutdown-automation` - Clean shutdown

## Testing

```lisp
(asdf:test-system :cl-automation)
```

## Architecture

```
cl-automation/
├── package.lisp      ; Package definitions and exports
└── src/
    ├── util.lisp     ; Utilities (ID gen, cron parser, priority queue)
    ├── trigger.lisp  ; Trigger types and evaluation
    ├── scheduler.lisp; Upkeep management and scheduling
    └── executor.lisp ; Execution engine
```

## Thread Safety

All public operations are thread-safe. The scheduler and executor maintain internal mutexes for concurrent access.

## Custom Execution

Provide a custom execution function to integrate with your blockchain:

```lisp
(defun my-execute-fn (upkeep perform-data)
  "Execute upkeep on chain."
  ;; Your blockchain interaction here
  (send-transaction (upkeep-target upkeep)
                    (upkeep-perform-data upkeep)))

(initialize-automation :execute-fn #'my-execute-fn)
```

## License

MIT License. See LICENSE file.

## Origin

Extracted from the CLPIC project (Common Lisp P2P Intellectual Property Chain).
