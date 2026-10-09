# Offline Buffering

Keep records on disk while the collector is unreachable.

## Overview

Exported batches go through a disk buffer in Application Support, in a directory excluded from
backups. When the collector cannot be reached, the batch stays on disk and is retried with back-off
(at most once a minute); once it is delivered it is deleted. A batch the collector rejects
permanently (any status except 429, 502, 503 and 504) is dropped instead of retried.

The buffer keeps at most 16 MB and 6 hours of data. Each batch holds at most 100 records, and a
batch stored on disk may be up to 1 MB.

``OTelTelemetry/flush()`` pushes everything recorded so far through the buffer to the network. It
can block for up to ``OTelConfiguration/exportTimeout`` per stage, so call it rarely —
``AppLifecycleObserver`` calls it when the app moves to the background.
