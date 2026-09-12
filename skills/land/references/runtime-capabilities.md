# Runtime capabilities for landing a PR

Use the current session's tool descriptions and the private fleet configuration to choose a
supported route. Do not assume a tool or model exists because an older run used it.

| Need | Required capability |
|---|---|
| Independent adversarial review | A review agent, review tool, or separate process that can inspect the candidate without editing it. This skill requests that independent pass. The current author's self-review cannot satisfy it. |
| Hosted review | The repository's configured reviewer, with evidence tied to the current PR head. Local review does not replace this gate. |
| Delegation | A callable agent or process API permitted by the current task and runtime. A tool that creates user-visible tasks only on explicit request is not a general subagent API. |
| Waiting | Event waits or bounded status polling supported by this runtime. Obey its timeout and communication rules. |
| Scheduled continuation | An automation capability, only when the owner requested later or recurring work. An ordinary landing request does not authorize a new schedule. |

Resolve provider choice, spending caps, and any excluded models from the existing fleet policy.
Do not install a provider, choose a paid fallback, or change the policy to make a route available.

If a required capability is absent, complete the remaining authorized preparation and report the
missing gate. Hosted-review unavailability does not permit merge. The registry's explicit
`review_bot: none` setting is the existing exception; acknowledge it in the summary.

Before sharing a diff or artifact with a review process, apply the prepublication scan in `land`.
Pass only the repository evidence the review needs. Keep private brain content out of bundles.
