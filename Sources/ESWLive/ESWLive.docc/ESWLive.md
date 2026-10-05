# ``ESWLive``

Own live view state on the server, serialize events, and publish render updates.

## Overview

A ``LiveView`` defines how to mount state, handle an event, and render HTML.
``LiveSession`` owns one instance's state and serializes complete asynchronous
operations. ``LiveHost`` manages instances for a route, binding them to trusted
owner tokens and expiring them after a fixed lifetime.

This library re-exports `ESW`, including `#live` and `ESWLiveRender`. It does not
install HTTP routes. An adapter supplies initial HTML, browser assets, event POSTs,
and the SSE stream, along with the application's session and CSRF checks.

> Important: This is the development runtime, with process-local state and its own
> protocol. It does not implement the Phoenix LiveView wire protocol or preserve
> sessions across server restarts.

## Topics

### Build a live feature

- <doc:WritingALiveView>
- <doc:LifecycleAndEvents>
- <doc:BrowserIntegration>

### Application contract

- ``LiveView``
- ``LiveContext``
- ``LiveEvent``
- ``LiveError``

### State and instance ownership

- ``LiveSession``
- ``LiveHost``
- ``LiveMount``
- ``LiveUpdate``

### Browser resources

- ``LiveAssets``
