# Sessions

Group records into sessions that follow Grafana Faro's rules.

## Overview

Every span and log record carries `session.id`, and `session.previous_id` when there was an
earlier session. Session ids are random and are not secrets.

With ``SessionPolicy/faro`` (the default) a session ends after 15 minutes without a record or after
4 hours in total. The next record starts a new session: telemetry emits `session.end` for the old
one and `session.start` for the new one. ``OTelTelemetry/resetSession()`` ends the current session
on demand, for example at sign-out.

Every launch starts a new session. Only its id is stored (in `UserDefaults`), so that the first
session after a launch can carry the previous one as `session.previous_id`. Records about the past —
MetricKit reports, or an event with an explicit timestamp — join the session that is current when
they are recorded; they never end or rotate it.

`session.id` is on the records rather than on the Resource because the Resource is fixed for the
pipeline's lifetime, while sessions rotate.
