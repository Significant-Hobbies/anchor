# Indulge and Habits consolidation

Decision date: 2026-08-24

Anchor is the sole maintained product for planning a day, following it with a
focus timer, recording interruptions, explaining schedule divergence, and
replacing automatic time with something deliberately chosen. Indulge/Habits is
a retired predecessor, not a second product competing for the same time.

## Carried into Anchor

- The original onboarding hero, all 24 illustrated behavior-pattern choices,
  and all eight illustrated life directions.
- The distinction between intentional enjoyment and time that ran on automatic.
- Private, optional pattern and life-direction selections with no diagnosis,
  streak, score, or moral judgment.
- Evidence-linked replacement suggestions after a real schedule gap.

The assets and their provenance live in Anchor. The first-run experience also
includes a real park-and-return rehearsal, so it reaches Anchor's core value
without reproducing Indulge's entire questionnaire.

## Mapped to Anchor

| Indulge/Habits responsibility | Anchor owner |
| --- | --- |
| recurring practices | schedule templates and recurring plan blocks |
| one conscious trade | a planned block linked to a behavior pattern and life direction |
| focus/interruption journal | focus sessions, captured distractions, and divergence events |
| completed-trade history | Day Review, export, and local MCP queries |
| pattern reflection | private behavior profile and evidence-linked suggestions |

## Intentionally retired

- The separate Life → Trade → History application shell.
- The duplicate Focus journal.
- The 12-question identity and behavior interview; name and gender do not help
  Anchor explain a schedule gap, and deeper causal questions are more truthful
  when asked about a real event.
- The authored 40 MB scene-plate/RealityKit room system, future-life card,
  privacy-lock flow, and standalone graduation concept.
- A separate Habits card or roadmap inside the Significant Hobbies Hub.

These remain in Git history as product research, not active dependencies.

## Compatibility retained

No migration or destructive cleanup is part of this consolidation. Preserve:

- bundle identifier `com.significanthobbies.indulge`;
- the existing SwiftData types, CloudKit container, App Store Connect/TestFlight
  record, and signed builds;
- Personal Platform's `habits` domain, records, callbacks, and typed contracts;
- `habits.significanthobbies.com` and `indulge.significanthobbies.com` as
  compatibility resources until a separately approved redirect or retirement;
- the Indulge repository and local checkout as recoverable source history.

The Indulge checkout is therefore unnecessary for ongoing Anchor development,
but it should not be deleted until these uncommitted changes are safely retained
in Git or another backup.
