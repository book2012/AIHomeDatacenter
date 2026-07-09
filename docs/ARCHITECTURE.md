# AIControlCenter Architecture

## Core Principle

AIControlCenter is the Brain.

Workers execute.

Ubuntu is only one Worker.

## Layered Architecture

AIControlCenter

1. Dashboard API
2. Monitoring Snapshot
3. Agent Framework
4. Scheduler
5. Power Manager
6. Session Manager
7. Task Execution Manager
8. Task Registry
9. WorkerFactory
10. WorkerClient
11. Runner
12. Worker Protocol
13. Workers

## Worker SDK

Worker SDK provides a common interface for all Workers.

Current implementation:

- UbuntuWorkerClient

Future implementations:

- GPUWorkerClient
- WindowsWorkerClient
- NASWorkerClient
- CloudWorkerClient

## Runner

Runner separates execution method from Worker logic.

Current Runners:

- LocalRunner
- SSHRunner

## Task Policy

All work must be registered as a Task.

Shutdown is allowed only when no running tasks exist.

## Recovery Policy

Recovery follows:

Detect
→ Report
→ Suggest
→ Execute

Automatic recovery is not enabled by default.
