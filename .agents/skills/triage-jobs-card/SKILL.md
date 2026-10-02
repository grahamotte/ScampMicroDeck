---
name: triage-jobs-card
description: Triage production job issues into deduplicated Planned Linear cards and complete the triage tracking card when requested.
---

# Triage Jobs Card

1. Use the repository's `triage-jobs` skill when available for its application-specific investigation. Otherwise use the `prod-debug` skill's read-only tools and inspect the repository's job schema and code to investigate failed and blocked production jobs from the last 24 hours. Do not assume another application's tables or job states exist. Do not fix code or mutate production during triage.
2. Group failures by cause and affected job or domain. Include occurrence counts, latest occurrence, representative errors, and evidence from relevant recent commits and deployed changes. Distinguish ongoing issues, possibly fixed issues needing monitoring, and expected or unaddressable conditions.
3. For each actually addressable issue, search the configured Linear team's existing cards with `mise linear`. Reuse a matching card and comment only when new information adds value. Otherwise create a card in Planned with a clear problem description and supporting evidence. Do not create cards for expected conditions or issues that cannot be addressed.
4. Comment on the triage tracking card with the complete list of findings, including conditions without cards and the identifiers of all created or reused cards.

Complete the triage card directly without review when investigation and reporting cover its whole scope. No PR is needed for triage alone. If required production data or tools are unavailable, record the blocker and move it to Planned. Remove the working tag when running for the manager.
