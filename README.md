# AIControlCenter

AIControlCenter is the Brain and Control Plane for AI Home Infrastructure.

It orchestrates Workers, Agents, Tasks, Sessions, Scheduling, Monitoring, Power Policy, and Dashboard APIs.

Ubuntu Storage Server is the first Worker, not the final goal.

## Architecture

AIControlCenter
→ Worker SDK
→ WorkerFactory
→ WorkerClient
→ Runner
→ Worker Protocol
→ Workers

## Current Worker

- Ubuntu Storage Server

## Future Workers

- GPU Worker
- Windows Worker
- NAS
- Raspberry Pi
- Cloud Worker

## Completed Core Modules

- Worker SDK
- Runner Interface
- LocalRunner
- SSHRunner
- UbuntuWorkerClient
- WorkerFactory
- Worker Command API
- Task Registry
- Task Execution Manager
- Multi-worker Session Manager
- Scheduler Core
- Power Manager
- Agent Framework
- Monitoring Snapshot
- Dashboard API Core

## Test Status

23 tests passed.

## Principle

Control Center thinks. Workers execute.
