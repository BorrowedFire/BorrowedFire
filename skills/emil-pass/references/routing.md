# Routing an Emil pass

Pick **at most four** references per pass. Start from the default set for the project type, then
swap one in only when the surface needs it (see *Swaps*). Paths are relative to the trove's
`skills/` folder (see `trove.md`) unless marked *installed*.

## Defaults by project type

### Expo / React Native

1. `animate-expo` (*installed*) — build recipes: thread, properties, spring or timing, gesture
   hand-off, haptics, Reduce Motion. An installed copy may carry local fixes, so prefer it over
   the trove's copy.
2. `animate-app` (*installed*) — the lead for app motion. Where it differs from Emil, it wins:
   no universal durations or spring presets, and keyboard activation keeps feedback.
3. `find-animation-opportunities` — the gate for adding motion.
4. `remove-animations` — the gate for subtracting motion.

### Native iOS (SwiftUI)

1. `animate-app` (*installed*) — lead, as above.
2. `apple-design` — response, direct manipulation, interruptibility, springs, velocity
   hand-off, spatial consistency. **Skip its "Materials & depth" section**: it targets web
   translucency, and SwiftUI materials follow the platform and `DESIGN.md`.
3. `gestures` — drag, swipe, sheet, and hold behaviour.
4. `choreograph` — when several elements move together.

### Web app

1. `review-animations` — the review bar and output discipline.
2. `remove-animations` — subtract first.
3. `find-animation-opportunities` — then add what passes the gate.
4. `emil-design-eng` for component polish and interaction detail, **or** `animate` when the
   fix is building a new animation.

### Marketing site

1. `mobile-native` — tap highlight, sticky hover, `100vh`, input zoom, and the other
   phone-browser fixes.
2. `remove-animations` — marketing pages collect decorative motion.
3. `emil-design-eng` — use its **Review Checklist** section only.

**Installed skill missing:** use the trove's `animate-expo` in place of the installed one. For
`animate-app`, swap in `apple-design` (SwiftUI) or `gestures` (Expo), and say so in the report.

## Swaps

Replace the lowest-value default with one of these when the surface calls for it:

| Signal on the surface | Swap in |
|---|---|
| visible jank, dropped frames, stutter on scroll (web) | `animation-performance` |
| several elements entering or changing together | `choreograph` |
| drag, swipe, fling, or dismissible sheet | `gestures` |
| layouts that may break on long names, empty lists, huge counts, other scripts | `break-ui` (findings only; its demo-data toggle is not a fix to ship) |

For Expo jank, stay with `animate-expo`: property and thread choice are its steps 4 and 6.

## Not routed

These stay out of an Emil pass: `improve-animations`, `ask-emil`, `animation-vocabulary`,
`pick-ui-library`, `prototype`, `ask-sonner`, `learn-taste`, `write-swift`. They answer
questions, pick libraries, or teach, rather than review a surface; `write-swift` overlaps the
project's own Swift rules.

## Conflicts

When a reference disagrees with the project, the precedence in `SKILL.md` step 2 decides. Note
each conflict you resolve in the "left alone on purpose" rows.
