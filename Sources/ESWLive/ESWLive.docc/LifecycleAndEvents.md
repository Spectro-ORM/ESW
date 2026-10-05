# Lifecycle, events, and ownership

Understand when a view mounts, how retries work, and when its state disappears.

## Overview

### Two mount phases

1. Creating a ``LiveSession`` calls `mount` with `isConnected == false` and renders
   initial HTML for the HTTP response.
2. The first `connect()` or `subscribe()` calls `mount` again with
   `isConnected == true`. That state replaces the initial state and advances the revision.
3. Further connections reuse connected state and receive a complete snapshot.

Mount must tolerate both calls. Avoid unconditional, non-idempotent external work
in mount. `LiveContext.parameters` and `.session` are chosen by the server adapter;
route/query data still needs application validation, and session data must come
from a trusted source.

### Serialized event handling

The session queues the entire async operation, including suspension, render,
state commit, and publication. A successful handler advances the revision even
when its HTML does not change. Throwing retains the previous state and HTML,
advances the revision, and publishes an empty patch without a successful event ID.

Payload, lifecycle, queue-capacity, and stale-revision errors rejected before
handler admission do not consume a revision. ``LiveError`` describes runtime
rejections; application handlers can throw their own errors too.

Request cancellation does not cancel an accepted mutation. Session closure cancels
its jobs cooperatively and prevents further state commits. Neither mechanism can
roll back database writes, network requests, or other external effects; those
operations need the application's transaction and idempotency policy.

### Retrying and resynchronizing

The last 128 admitted event outcomes are retained per instance, including failures.
An identical event ID and payload returns the original outcome. Reusing the ID
with different content produces ``LiveError/reusedEventID``.

Browser events must supply the current `baseRevision` through the HTTP adapter.
After an outcome leaves the retry cache, that old revision prevents re-execution.
The low-level Swift API permits nil revisions for trusted server events; it cannot
provide that eviction protection when no revision is supplied.

Updates carry a revision, optional base revision, patch, and optional successful
event ID. A nil base revision denotes a complete snapshot. The bundled browser
client can receive the same update through POST and SSE and applies it once.
Reconnection resynchronizes with a full snapshot, not replay from `Last-Event-ID`.

A session supports one current subscription: opening a new one finishes the
previous stream. Slow consumers are disconnected if their bounded buffer fills.

### Own instances with a host

``LiveHost`` binds each random instance ID to a nonempty owner token. The adapter
must obtain that token from a trusted server-side session, never from an arbitrary
browser field. IDs identify instances; they are not authorization credentials.

Use `mount(owner:context:)`, `subscribe(_:owner:)`, and `handle(_:owner:event:)`
at browser-facing boundaries. Call `invalidate(owner:)` before clearing a login
session or after permissions are revoked. It closes existing streams and prevents
already-suspended mounts from registering for that owner.

`send(_:event:)` intentionally bypasses owner checks for trusted server-originated
events. It still uses the same session handler and needs a connected instance.
Do not expose it directly as an unauthenticated route.

`remove(_:owner:)` removes one owned instance. `shutdown()` permanently closes the
host. An invalidated owner may mount again after the application's authorization
has succeeded; a shut-down host cannot accept new mounts.

### Resource limits

| Resource | Default |
| --- | --- |
| Host instances, including pending mounts | 1,000; configurable on `LiveHost`. |
| Instance lifetime | One hour from completed mount; configurable and not extended by activity. |
| Pending session operations, including the running one | 32; configurable on `LiveSession`. |
| Buffered stream updates | 16; configurable on `LiveSession`. |
| Remembered event outcomes | 128. |
| Event ID and name | 128 UTF-8 bytes each; nonempty. |
| Distinct field names / values per field | 128 each. |
| Field-key length | 256 UTF-8 bytes. |
| Aggregate field keys and values | 65,536 UTF-8 bytes. |

All state, streams, and retry history are process-local. Expiry closes the
instance; a browser reload creates a new one. There is no cross-node registry,
restart persistence, nested stateful live components, or managed lifecycle for
tasks created by application code.
