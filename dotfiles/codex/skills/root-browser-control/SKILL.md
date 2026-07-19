---
name: root-browser-control
description: Route every in-app Browser operation, including navigation, inspection, clicking, typing, screenshots, and browser testing, through the visible root task.
---

# Root Browser Control

- Root task: use the in-app Browser directly; never delegate Browser calls.
- Subagent: do not initialize or use Browser; send or return the precise Browser request to the root task.
