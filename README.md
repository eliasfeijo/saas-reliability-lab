# SaaS Reliability Lab

A practical exploration of what actually breaks when an early-stage SaaS starts getting real users.

This repository is not a productivity app and not a UI project.

It is a reliability and synchronization experiment simulating a small SaaS product where users:

* go offline and reconnect hours later
* log in from multiple devices
* receive scheduled notifications
* perform background actions
* create concurrent data changes

The goal is to study **failure modes, recovery strategies and system behavior under imperfect conditions** — the situations that typically appear right after a startup launches publicly.

---

## Why this exists

Many startups launch with a simple architecture:

* a frontend
* a database
* an authentication provider
* some background tasks

It works perfectly… until users behave like real users.

From my experience, the first serious problems rarely come from traffic volume.
They come from **state inconsistency**.

Examples:

* users performing actions offline
* duplicated writes after reconnection
* missed background jobs
* push notifications not delivered
* auth sessions diverging across devices
* silent data conflicts

This project was created to simulate and understand those situations before they happen in production.

---

## System Overview

The system models a small task-management SaaS with:

Client:

* Offline-first local storage
* Sync queue
* Auth session persistence
* Retry logic

Backend:

* Authentication provider
* Database
* Background job scheduler
* Notification dispatcher

### Simplified Architecture

```
Client (PWA / Flutter Web)
      |
Local storage (offline changes)
      |
Sync Queue → Retry / Backoff
      |
Supabase (Auth + Database)
      |
Scheduled jobs / notification service
      |
Push notifications to client
```

Key idea:
**The client is allowed to be wrong temporarily.
The system must still converge to a consistent state.**

---

## Key Engineering Decisions

### 1) Offline-First Local State

The client stores changes locally before the network request.

Why:
Network reliability cannot be assumed, especially on mobile devices.
Users must be able to interact with the system even without connectivity.

Consequence:
The backend must handle delayed writes and replayed actions.

---

### 2) Sync Queue Instead of Immediate Writes

Instead of writing directly to the API, operations are queued.

This allows:

* retry after reconnection
* batching
* recovery from transient failures

But introduces a new class of problems:
**duplicate operations and ordering issues.**

---

### 3) Idempotent Operations

Every write operation must be safe to execute multiple times.

Without idempotency, reconnection events create:

* duplicated records
* inconsistent state
* corrupted timelines

---

### 4) Conflict Scenarios

Multiple devices may edit the same entity.

The system needs a strategy:

* last-write-wins?
* timestamp reconciliation?
* merge?

This project experiments with basic reconciliation and highlights where a real SaaS would need stronger guarantees.

---

### 5) Background Jobs & Notifications

Notifications cannot be triggered directly by the client.

They require:

* a trusted server
* scheduling
* retry policies

The project includes a simulated notification workflow to demonstrate:

* missed schedules
* server downtime
* delayed execution

---

## Failure Scenarios Simulated

The interesting part of a system is not when it works — but when it partially works.

This project explores situations like:

* user creates 15 tasks offline and reconnects
* two devices update the same record
* network drops during sync
* expired auth token during queued operations
* scheduled notification while server unavailable
* duplicated retries after timeout

---

## What Would Be Required in a Real Company

If this were production software, I would add:

Observability:

* centralized logging
* distributed tracing
* error tracking

Reliability:

* background queues (SQS / RabbitMQ / BullMQ)
* idempotency keys
* retry policies with exponential backoff
* dead-letter queues

Security:

* refresh token rotation
* session invalidation
* rate limiting

Scalability:

* API boundaries
* queue-based workers
* cache layer
* circuit breakers

---

## Tech Stack

Client:

* Flutter (Web PWA)
* Dart
* Local storage persistence

Backend services:

* Supabase (Auth + Postgres)
* Web Push notifications

Infrastructure concepts explored:

* offline-first synchronization
* eventual consistency
* retry strategies
* failure recovery

---

## Current Status

The notification server is intentionally not running continuously.

This is deliberate:
some failure scenarios described above depend on service interruption and recovery behavior.

---

## What this repository is meant to demonstrate

This project is meant to answer a practical question:

> How should a backend behave when users and networks are unreliable?

The code matters less than the reasoning.

The real goal is to document the architectural thinking required to keep a small SaaS stable as it grows from its first users to real usage.
