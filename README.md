# AIControlCenter

AIControlCenter is the Brain of the AI Home Infrastructure.

It is not a dashboard.

It is the Control Plane responsible for orchestrating all Workers in the infrastructure.

---

## Architecture

AIControlCenter

↓

Worker SDK

↓

Runner

↓

Worker Protocol

↓

Workers

Current Worker

- Ubuntu Storage Server

Future Workers

- GPU Worker
- Windows Worker
- NAS
- Raspberry Pi
- Cloud Worker

---

## Current Sprint

### Completed

- Python Development Environment
- Pytest Framework
- Worker SDK
- Runner Abstraction
- LocalRunner
- SSHRunner
- UbuntuWorkerClient
- WorkerFactory
- workers.yaml
- Worker Health Parser
- Worker Command API
- Task Registry
- Task Execution Manager
- Session Manager

---

## Current Architecture

AIControlCenter

↓

WorkerFactory

↓

WorkerClient

↓

Runner

↓

Worker Protocol

↓

Ubuntu Worker

---

## Design Principles

- Control Center First
- Worker Agnostic
- Infrastructure as Code
- Git First
- Documentation
- Automation
- Long-term Maintainability

