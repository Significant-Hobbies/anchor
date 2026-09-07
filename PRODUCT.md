# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

People who want to live a deliberate day rather than merely maintain a task
list. They make a schedule containing work, commitments, recurring routines,
rest, and enjoyable activities, then need a low-friction way to understand what
actually happened when reality diverges from that plan.

The primary operating context is one private owner moving between Mac, iPhone,
and Apple Watch. They may be planning tomorrow, starting the current block,
capturing an interruption at the moment it happens, or reflecting at the end of
the day.

## Product Purpose

Anchor helps a person plan a realistic day, keep the current intention visible,
capture what changes it, and learn why the day they lived differed from the day
they planned. It combines recurring habits, timed focus, interruption evidence,
and non-moralizing pattern change in one loop.

Success is not perfect adherence. It is a more realistic plan, fewer automatic
departures that the person did not choose, quicker recovery from interruptions,
and better protection for the activities they genuinely want in their life.

## Positioning

Anchor explains schedule divergence rather than merely displaying a calendar or
counting productive minutes. It separates estimation error, deliberate
re-planning, internal pulls, external interruptions, human needs, and unknown
gaps, then offers evidence-linked changes for a future day.

## Operating Context

- The daily loop starts with replacing unwanted habits with good ones. A habit
  can be checked off directly; giving it a time is optional.
- The owner can select a day, edit its entries, copy them to another day, and
  add a spontaneous entry. Copies preserve planned content and project context,
  start unfinished, and leave existing destination entries intact.
- Entries can carry a project and start the same focus timer. Interruption
  capture offers park-and-continue, pause-and-return, and end-session actions.
- Habit progression and daily confirmation are not prerequisites for using the
  planner. Historical records remain available without driving extra prompts.
- A day contains dated plan blocks sourced from local recurring routines,
  one-off intentions, and eventually read-only calendar commitments.
- A focus-capable plan block can become an Anchor session without duplicating
  timer state; wall-clock session timing remains authoritative.
- The person can capture an interruption immediately from Mac, iPhone, or Watch
  and can decline a resume prompt without friction.
- End-of-day review reconciles the plan with observed sessions, completions,
  deliberate changes, and explicitly unknown time.
- First run may ask which enjoyable or automatic activities repeatedly take
  longer than intended and what the person wants to make room for instead. Both
  questions are optional and private.

## Capabilities and Constraints

- Native SwiftUI applications for macOS, iOS, and watchOS share AnchorCore and
  AnchorUI. The Watch is a remote, not a reduced analytics or planning app.
- SwiftData is the immediate local store; private CloudKit supports Apple-device
  continuity. Models remain CloudKit-compatible: optional relationships, no
  unique constraints, and defaults or optional values for every attribute.
- Optional Hub sync may send finished-session summaries. Distraction text,
  behavioral profile selections, divergence notes, and private reflections do
  not leave local/private Apple storage.
- Timing derives from wall-clock timestamps through TimeAccount, never an
  incrementing counter.
- Apple Intelligence is optional. Classification and review remain usable with
  deterministic rules, and generated summaries may phrase evidence but may not
  invent causes.
- No account wall, analytics SDK, remote model, automatic app-content capture,
  opaque schedule mutation, global adherence score, or moralized streak.
- Existing Anchor and Indulge bundle identifiers and stores remain intact until
  a separately specified and verified migration is ready.

## Brand Commitments

- Name: Anchor.
- Voice: concise, calm, adult, factual, private, and non-moralizing.
- Anchor's ink-and-paper focus language is the operational identity. Colour
  belongs primarily to authored doodles and known interruption origins, never
  to a bluish wash across the interface.
- Anchor is doodle-first. The original Indulge/Habits line-art world is the
  canonical product personality across planning, focus, habits, review, and the
  public landing. Operational screens use one purposeful scene, annotation, or
  state illustration at a time; controls and data remain quiet, native, and
  immediately legible rather than becoming a decorative cartoon dashboard.
- Intentional enjoyment is not failure. A conscious change of plan is a valid
  outcome and must remain distinct from an automatic pull.

## Evidence on Hand

- Anchor ships tested wall-clock focus sessions, interruption capture,
  internal/external/mixed classification, analytics, export, MCP reads, and
  native Mac/iPhone/Watch surfaces.
- The Indulge repository contains an original generated 24-item indulgence art
  library, life-direction artwork, authored scene families, and recorded asset
  provenance. These are local project assets rather than third-party artwork.
- No user research, behavioral outcome study, adherence benchmark, or evidence
  that schedule recommendations improve a person's day exists yet. Future work
  must not fabricate it.

## Product Principles

1. Diagnose the plan as readily as the person.
2. Show evidence and provenance; preserve Unknown rather than guessing.
3. Make deliberate re-planning neutral and intentional enjoyment legitimate.
4. Ask for as little manual accounting as honest causality allows.
5. Suggest a small change the owner can accept, never rewrite life opaquely.

## Accessibility & Inclusion

The complete planning, focus, capture, and review loop must support Dynamic
Type, VoiceOver, keyboard operation on Mac, Dark Mode, increased contrast, and
Reduce Motion. Artwork always has an equivalent textual label and is never the
only carrier of selection or causal meaning.
