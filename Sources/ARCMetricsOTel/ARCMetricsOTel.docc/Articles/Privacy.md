# Privacy

Know what leaves the device, scrub it, and declare it.

## Overview

The package's own attributes are fixed and contain no personal data; the test suite pins them.
Everything you pass — attributes, event names, screen names, span names and error types — leaves
the device as you write it. Span names from ``OTelTracer`` are `StaticString` constants; event names
(``OTelTelemetry/emitEvent(_:attributes:severity:timestamp:)``) and screen names
(`trackScreen(_:attributes:)`) are runtime strings, and a span's error type is whatever the thrown
error's type is called. Keep all of them constant and never put personal data in attributes.

### Attribute scrubbing

Every record's attributes go through ``OTelConfiguration/attributeScrubber`` inside the telemetry
actor, before the record is created. ``AttributeScrubber/default`` follows OpenTelemetry's semantic
conventions and Apple's App Privacy data types:

- It drops OpenTelemetry's personal-data attributes (`user.email`, `user.full_name`, `user.name`,
  `user.id`, `user.hash`, `enduser.id`, `enduser.pseudo.id`, `geo.postal_code`).
- It drops any attribute whose key has a segment naming contact information, a location or a
  credential — `email`, `phone`, `address`, `lat`, `lon`, `latitude`, `longitude`, `password`,
  `passwd`, `token`, `jwt`, `bearer`, `secret`, `authorization`, `cookie`, `credential(s)`, `apikey`,
  `privatekey`, `userid` — splitting keys on `.`, `_`, `-` and camelCase and also joining adjacent
  words, so `x-api-key` and `user_id` are dropped. This also drops standard keys such as
  `server.address` and `client.address`.
- In `url.*` values it replaces credentials with `REDACTED:REDACTED`, as the semantic conventions
  require, and cuts the query and fragment; `url.query` and `url.fragment` are dropped.

The default is a **best-effort backstop**, not a guarantee: a key such as `customer`, `ip` or
`nickname` passes. Add your own rules after it:

```swift
let scrubber = AttributeScrubber.default.then(AttributeScrubber { attributes in
    attributes.filter { !$0.key.hasPrefix("customer.") }
})
```

`session.id` and `session.previous_id` are added after scrubbing, so a scrubber can neither remove
nor forge them.

### Privacy manifest

The package ships its own `PrivacyInfo.xcprivacy`, which Xcode merges into your app's privacy
report:

- **Required-reason API:** `UserDefaults` (`CA92.1`), to keep the last session id.
- **Collected data, not linked to the user and not used for tracking:** Crash Data, Performance
  Data and Other Diagnostic Data (app functionality); Product Interaction (analytics); Device ID —
  `session.id` and the persisted `session.previous_id`, stamped on every record (app functionality
  and analytics).

### What your privacy label must say

| Data the app sends | App Privacy data type |
|--------------------|-----------------------|
| `app.crash` | Diagnostics — Crash Data |
| `MXMetricPayload`, `app.hang` | Diagnostics — Performance Data |
| Your spans, `session.start` / `session.end` | Diagnostics — Other Diagnostic Data |
| `app.screen.view`, `device.app.lifecycle` | Usage Data — Product Interaction |
| `session.id`, `session.previous_id` | Identifiers — Device ID |

`session.previous_id` is persisted across launches, so a collector can chain every session of an
install; with `device.model.identifier`, `os.version` and the client IP it works as a pseudonymous
install identifier. The data is **not linked** to the user only while it carries nothing that
identifies them: as soon as your attributes (or your collector) join it to an account, a user id or
other personal data, declare it as **linked to you**.
