---
title: "Why focus timers should derive elapsed time from the wall clock"
slug: "why-focus-timers-should-derive-elapsed-time-from-the-wall-clock"
target_query: "how to build a focus timer"
search_intent: "Informational/Technical"
meta_title: "Building Reliable Focus Timers with Wall-Clock Time"
meta_description: "Learn why robust focus timers rely on absolute wall-clock timestamps rather than incrementing tick counts to survive device sleep, sync, and app backgrounding."
---

## Outline

1. **Introduction**
   - The fundamental problem with timer state in modern operating systems.
2. **The fragility of incrementing counters**
   - What happens during device sleep and app suspension.
3. **The wall-clock approach defined**
   - Storing states instead of running totals.
4. **Concrete scenarios where wall-clock timing wins**
   - **Scenario 1: App backgrounding and sleep.**
   - **Scenario 2: Device continuity and syncing.**
   - **Scenario 3: Pausing and resuming.**
5. **Architectural benefits of the wall-clock model**
   - State predictability and deterministic testing.
   - Decoupling the UI representation from the timing logic.
6. **Next Action**
   - Practical steps to transition an existing tick-based implementation.
7. **Source Notes (Review Only)**
   - Internal references to Anchor's repository and known constraints.

## Introduction

At first glance, building a focus timer appears to be a straightforward exercise in scheduling. The developer instinct is often to initialize a variable at zero and schedule a timer function to increment that variable every second. When the user taps start, the timer begins ticking; when they tap pause, the ticking stops. This mental model—the ticking stopwatch—is so deeply ingrained in our understanding of timekeeping that it shapes the initial architecture of nearly every timer application.

However, modern operating systems are not simple clockwork mechanisms. They aggressively manage power, memory, and background execution. An application that relies on an active, continuous tick count is operating under the false assumption that it has uninterrupted access to CPU cycles. When an application is suspended, sent to the background, or when the device itself goes to sleep, those scheduled ticks simply do not occur.

The consequences of this design flaw are immediately apparent. You start a session, close your laptop screen to move to another room, and when you open it five minutes later, your timer has only advanced by a few seconds. This discrepancy destroys the utility of the tool. A focus timer must be an absolute anchor of truth; if the user cannot trust its reporting of elapsed time, the tool fails its primary purpose.

To build a robust, reliable focus timer, we must discard the illusion of the continuous tick. We must shift our perspective from actively counting seconds to passively observing the passage of time between fixed events. This means deriving elapsed time entirely from absolute wall-clock timestamps.

## The fragility of incrementing counters

To understand why the wall-clock approach is necessary, consider a naive implementation where a scheduled timer fires once per second.

When a user switches away from the timer application, the operating system may deprioritize the timer process. On mobile platforms, background execution is strictly limited. The OS will suspend the app, pausing its execution entirely. The scheduled timer stops firing. When the user returns to the app, execution resumes, but the missed ticks are lost forever. The timer now lags behind reality.

Device sleep exacerbates this issue. If a user starts a timer on their Mac and then closes the lid, the entire system enters a low-power state. No user-space applications are executing. When the machine wakes up, an incrementing counter will simply pick up where it left off, oblivious to the fact that real-world time has elapsed.

Furthermore, operating systems routinely terminate suspended applications to reclaim memory. If an incrementing timer is terminated, its current state is lost unless it is aggressively writing its running total to a database every single second—a catastrophic antipattern for battery life and disk wear.

Even in optimal conditions, relying on fixed intervals introduces drift. Software timers are not precise hardware interrupts; they are requests made to the operating system's run loop. Over a long session, these inaccuracies accumulate.

## The wall-clock approach defined

The solution to these varied failure modes is architectural simplicity: stop counting. Instead of actively tracking time, the application should record the precise moments when the state of the timer changes, and calculate the elapsed time dynamically whenever it is needed.

This is the wall-clock approach. It relies on a foundational data structure that records, at minimum:
1. The absolute timestamp when the timer was started (the open interval).
2. The total amount of time accrued from previously closed intervals (the bank).

When the timer is running, the current elapsed time is not a stored value. It is a calculation: the difference between the current absolute time and the start timestamp, plus any previously banked time.

Let us examine this logic conceptually. When a user starts a session, the system records the start time. If the user leaves the app, the device goes to sleep, or the app is terminated, it does not matter. The timestamp is safely stored. When the user returns and views the UI, the application performs the calculation: now minus the start time. The result is perfectly accurate.

## Concrete scenarios where wall-clock timing wins

The advantages of deriving time from the wall clock are best illustrated through the concrete scenarios that cause naive implementations to fail.

### Scenario 1: App backgrounding and sleep

As previously established, modern devices frequently enter low-power states or suspend background processes. With a wall-clock model, a session is not "a countdown that ticks." It is a bank of already-earned seconds plus an open interval.

Imagine starting a session. The system records the start time. Five minutes later, you close your laptop. The application is suspended. Thirty minutes later, you open the laptop. The UI requests the current elapsed time. The underlying model retrieves the timestamp, subtracts it from the current wall-clock time, and correctly reports that thirty-five minutes have elapsed.

### Scenario 2: Device continuity and syncing

In an ecosystem where users move fluidly between devices, a focus timer should ideally follow them. A user might start a timer on their Mac, walk away from their desk, and want to check the remaining time on their iPhone.

If elapsed time is a running counter, syncing becomes a nightmare. Which device is the source of truth? If both devices are incrementing a counter simultaneously, syncing them will lead to duplicated time or complex, error-prone conflict resolution.

With a wall-clock model, syncing is trivial. The session state is simply the timestamp and the banked seconds. When the Mac syncs this state to the cloud, and the iPhone pulls it down, the iPhone performs the exact same calculation: now minus the start time. Because both devices share a common understanding of absolute time, they independently arrive at the exact same elapsed duration.

### Scenario 3: Pausing and resuming

Handling intentional pauses is essential for a focus timer. A pause is not simply stopping a counter; it is closing an interval.

Under the wall-clock model, when a user taps pause, the system calculates the duration of the current open interval and adds it to the banked seconds. It then sets the start timestamp to null.

The elapsed time is now entirely represented by the banked seconds. It remains static. When the user resumes the session, the system simply sets a new start timestamp to the current time. The total elapsed time is then the sum of the banked seconds and the new open interval. This operation is idempotent and perfectly preserves the integrity of the session.

## Architectural benefits of the wall-clock model

Beyond solving specific failure modes, adopting a wall-clock architecture yields significant benefits for the overall design and maintainability of the software.

### State predictability and deterministic testing

A pure timing model that does not rely on system timers or asynchronous delays is exhaustively unit-testable. The entire state of a session can be represented as a simple value type.

Testing the logic becomes a matter of injecting arbitrary timestamps. You can instantiate a session state, simulate an elapsed interval by passing a future date into the calculation function, and verify the output. You can verify that pausing correctly banks the time, and that resuming opens a new interval.

Because nothing touches the local data store or the system run loop during these calculations, tests are perfectly deterministic and run in milliseconds.

### Decoupling the UI representation from the timing logic

The wall-clock model enforces a strict separation of concerns. The timing logic is responsible only for maintaining the state and calculating derived values.

The UI is entirely decoupled from this truth. The UI layer can use a cooperative loop or an asynchronous task to poll the timing model every half-second and update the display. If the UI polling task is suspended, canceled, or delayed, it has absolutely no impact on the underlying data. The timer continues "running" in the data model because the passage of absolute time is inexorable.

When the UI loop resumes, it simply queries the model again and instantly reflects the correct, up-to-date reality. This decoupling is essential for building robust native applications where the UI layer is frequently subject to lifecycle interruptions.


## Internal Linking Opportunities

*   **Link to:** The main Anchor landing page (`/`) when discussing how the tool handles app backgrounding and sync.
*   **Link to:** A feature page on focus timers (if available) when mentioning intentional pauses and how they are handled.
*   **Link to:** The Anchor setup/download page in the "Next Action" section.

## Next Action

Review your current timer implementation. If it relies on a scheduled recurring function to mutate a running total variable, plan a refactor. Define a data structure containing a banked time numeric property and an optional start timestamp property. Rewrite your elapsed time function to return the sum of the banked time and the difference between the current absolute time and the start timestamp. Check the documentation for native tools that expect a wall-clock timestamp model.

## Source Notes (Review Only)

*   **Evidence base:** The architectural arguments in this draft are directly supported by `Sources/AnchorCore/Session/TimeAccount.swift`.
*   **TimeAccount logic:** The article accurately reflects the `TimeAccount` value type, explicitly describing its `bankedSeconds`, `plannedSeconds`, and `runningSince` properties. The explanation of pausing (`pause(at:)`), resuming (`resume(at:)`), and calculating elapsed time (`elapsed(at:)` using `max(0, now.timeIntervalSince(runningSince))`) mirrors the repository's logic.
*   **UI Decoupling:** The description of a cooperative loop updating the UI matches the `startTicking()` and `refreshNow()` implementation found in `Sources/AnchorCore/Session/FocusController.swift`.
*   **Live Activities:** The wall-clock architecture maps perfectly to native system features like iOS Live Activities, as seen in `publishLiveActivityStart()` and `liveActivitySnapshot()` in `FocusController.swift`.
*   **Product Constraints:** The article respects the constraints outlined in `PRODUCT.md` and `AGENTS.md`. It adopts a concise, factual, and non-moralizing tone. It emphasizes the principle that "Timing is derived from the wall clock, never from a tick count" as a hard constraint.
*   **Important Limitation:** While the article discusses syncing between Mac and iPhone, it is important to note internally that the Apple Watch is considered a "remote" (`AGENTS.md`), not an independent analytics or deep planning client. The watch creates and pauses sessions using the same underlying timestamp logic, but the primary source of truth and complex resolution remains on the broader platforms.
