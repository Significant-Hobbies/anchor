---
title: "On-device tagging with a deterministic fallback"
slug: "on-device-tagging-with-a-deterministic-fallback"
target_query: "on-device machine learning tagging fallback"
search_intent: "informational"
meta_title: "On-device Tagging with a Deterministic Fallback | Anchor"
meta_description: "How Anchor uses Apple's on-device foundation model for privacy-first tagging, and falls back gracefully to a deterministic ruleset when AI isn't available."
---

# On-device tagging with a deterministic fallback

**Outline:**
1. **Introduction:** The privacy constraints of personal data like distractions, necessitating on-device processing.
2. **The Problem:** Grouping free-form notes into structured categories without sending data to an external server.
3. **The Solution: Apple's Foundation Model:** Using Apple Intelligence for nuanced text classification, ensuring that all data remains on the device.
4. **The Reality: When Models Aren't Available:** Why a robust fallback is necessary (unsupported hardware, unsupported operating systems, user opt-out, or model assets currently downloading).
5. **The Deterministic Fallback:** How a comprehensive keyword-based rule system ensures consistent baseline functionality.
6. **Graceful Degradation:** How the fallback system interacts with and even improves the AI's performance, leading to a transparent user experience.
7. **Next Action:** Try Anchor's local-first analytics to see the tagger in action.

---

When building software that handles highly personal data, privacy isn't just a marketing bullet point; it is a structural requirement. For a focus and time-tracking app like Anchor, one of the most sensitive pieces of data is the "distraction note"—the honest, unfiltered reason why you broke your focus or interrupted your workflow.

These notes are incredibly personal. They might mention specific people by name, discuss sensitive work projects, or simply express private, unguarded thoughts that you would never share publicly. Because of this inherent sensitivity, they absolutely cannot be sent to a third-party server for processing. *[Internal Link Suggestion: Link to Anchor's Privacy Policy page]* Yet, to provide useful, actionable analytics that help users understand their habits, these free-form notes need to be grouped into structured categories.

The solution to this tension between privacy and utility is entirely local on-device tagging. By bringing the processing to the data rather than sending the data to the processing, we can maintain strict privacy guarantees. But what happens when the latest on-device machine learning models aren't available? This article explores how Anchor uses Apple's on-device foundation model for nuanced tagging, and how we implement a robust, deterministic fallback for the inevitable situations when the AI isn't an option.

## The problem of unstructured, private data

Anchor asks you to actively record what interrupted your focus. You might write "Slack from Ravi about the invoice", "roommate walked in to chat", or "ended up reading three Wikipedia pages on typography".

To build a useful "distraction leaderboard" that helps you adjust your workflow, the app needs to know that the first interruption is a digital message, the second is a physical person, and the third is a "rabbit hole".

Traditional web apps solve this by sending the raw text to a cloud-based API and getting a structured JSON response back. But for Anchor, distraction notes never leave the device. Period. Therefore, we need a reliable way to classify this text locally, using only the resources available on the user's Mac, iPhone, or Apple Watch. *[Internal Link Suggestion: Link to article on Anchor's Distraction Tracking feature]*

## The primary path: Apple's on-device foundation model

When available, Anchor takes advantage of Apple Intelligence (specifically via the `FoundationModels` framework) to classify both goals and distractions. We provide the on-device language model with a strict set of instructions and ask it to pick the most appropriate fit from a fixed set of categories.

For example, our prompt for classifying distractions explicitly defines boundaries:
> `"message"` is a chat or text arriving from a person, through any app — Slack, WhatsApp, iMessage, Discord, SMS. The app is what matters, not who sent it.
> `"person"` is ONLY for someone physically present interrupting in the room. If it arrived through a screen, it is never "person".

The foundation model inherently knows that "Ravi asked me about deploy timing on Slack" falls under the `message` category, while "Roommate walked in to chat" is clearly a physical `person`. It can understand the difference between a digital interruption and a physical one.

Furthermore, the model is capable of extracting 2 to 4 short lowercase keywords from your wording. This allows us to cluster repeated specific interruptions together without losing nuance. Because this model runs entirely locally on macOS and iOS devices equipped with the necessary neural engine hardware, the data remains completely private.

## The necessity of a fallback

If the foundation model is so capable, why build anything else? Because you simply cannot guarantee the model's availability for every user, on every device, at all times.

An app might find the on-device model unavailable for several reasons:
*   **Unsupported Hardware:** The user is running an older iPhone or Mac that does not support Apple Intelligence.
*   **Unsupported OS:** The app is running on an Apple Watch (`watchOS`), a platform where the large foundation model simply isn't shipped due to extreme memory constraints. When a user captures a distraction on their wrist, the watch needs a way to categorize it immediately. *[Internal Link Suggestion: Link to Anchor's watchOS companion app overview]*
*   **Opted Out:** The user has explicitly turned Apple Intelligence off in their System Settings. We must respect this choice.
*   **Still Downloading:** The model assets are significant in size and might still be downloading in the background when the user first opens the app.

In any of these scenarios, failing to tag the note is unacceptable. The app needs to gracefully degrade, providing a functionally identical, if slightly less nuanced, experience.

## The deterministic fallback: Heuristic Tagging

To solve this ubiquitous availability problem, Anchor includes a `HeuristicTagger`—a completely deterministic, rule-based fallback classifier. This is a meticulously crafted set of rules designed to catch common interruption patterns.

This tagger uses a prioritized list of keyword cues to bucket notes into categories. The order of this list is crucial: the first bucket with a hit wins. This sequential evaluation means that more specific cues intentionally override more general ones.

For example, consider how the system handles the note "slack message from mum". The tagger checks the input against our ordered rules:
1. It looks for meeting cues (`meeting`, `standup`, `zoom`). No match.
2. It looks for specific messaging apps (`slack`, `whatsapp`, `text from`). It hits on `slack`.

It instantly categorizes the note as a `message`. This prioritized ordering ensures that "slack message from mum" doesn't accidentally get tagged as `person` just because it contains the word "mum". The explicit mention of the channel (`slack`) is much stronger evidence of the *type* of interruption than the ambiguous presence of a person's name.

Similarly, we explicitly place strong physical presence cues (`knocked`, `walked in`) ahead of ambiguous messaging cues (`chat`) so that a physical arrival is always correctly identified.

The deterministic tagger also provides keyword clustering by extracting keywords through a process of stripping out a predefined set of common stop words ("the", "and", "really", "just") and taking the first few meaningful words that remain.

### Why the fallback helps the AI

The relationship between the deterministic fallback and the AI isn't just a simple primary/backup switch. The deterministic fallback actually serves as a highly useful hint for the foundation model when it *is* available.

When we prompt the Apple Intelligence model, we actually run the fast heuristic tagger first, and we append its guess to the prompt we send to the AI:
> A keyword matcher suggests: `[Fallback Category]`
> Use that suggestion unless the wording clearly points elsewhere.

Small on-device models can sometimes drift on subtle boundaries. For example, during early testing, we observed the model reading "Slack from Ravi" as a physical interruption (`person`). By explicitly handing the rule-matcher's guess (which correctly identified "Slack" as a `message`) to the AI as a hint, we anchor the model to a reliable baseline when explicit cues are present. This provides the best of both worlds: the strict reliability of the rules engine, combined with the AI's ability to override it if the deeper context truly demands it.

## The user experience of graceful degradation

When building this kind of dual-path system, transparency with the user is key. They should understand how their data is being handled. Anchor's settings surface a `TaggingService.Availability` state, letting the user know exactly why their tags might say "rules" instead of "on-device model".

If their device isn't eligible, the app clearly explains: "This device doesn't support Apple Intelligence. Anchor is using built-in rules instead." If they are on an Apple Watch, the interface notes that the phone or Mac will refine the tags later once the data syncs via CloudKit. *[Internal Link Suggestion: Link to Anchor's CloudKit Sync architecture post]*

By combining the nuance of an on-device language model with the rock-solid reliability of a deterministic fallback, you can build privacy-first features that work beautifully on day one, regardless of the user's hardware, operating system, or device settings. The user gets their distraction leaderboard, their data stays on their device, and the software remains robust in all conditions.

## Next Action
Want to see how this dual-path architecture looks in practice? Check your focus patterns in Anchor's History tab—all categorized entirely on your own device, ensuring your distraction notes remain yours alone.

---

### Source Notes (Not for Publication)
*   **`Sources/AnchorCore/Intelligence/TaggingService.swift`**: Defines the dual-path tagging architecture. Proves that distraction notes never leave the device. Shows the `Availability` enum detailing exactly why a model might be unavailable (`deviceNotEligible`, `notEnabled`, `modelNotReady`, `unsupportedOS`), which directly maps to the user-facing explanations. Shows the prompt instructions that explicitly define the boundaries (e.g., `message` vs `person`) and demonstrates how the heuristic fallback is injected into the prompt as a hint for the model.
*   **`Sources/AnchorCore/Intelligence/HeuristicTagger.swift`**: Contains the meticulously prioritized arrays `distractionCues` and `goalCues`. Shows the explicit ordering strategy where specific channels like `slack` intentionally win over terms like `mum`, and physical cues like `walked in` explicitly win over ambiguous terms like `chat`. Includes the hardcoded `stopWords` filtering logic used for deterministic keyword extraction.
*   **Limitations**: As explicitly noted in `TaggingService.swift` via compiler directives (`#if canImport(FoundationModels) && !os(watchOS)`), the foundation model path requires iOS/macOS 18+ and compatible hardware. The `watchOS` target explicitly excludes the model path entirely because `SystemLanguageModel` is marked unavailable on that platform. Therefore, the watch relies 100% on the heuristic fallback until the data syncs back to a more capable phone or Mac via the shared CloudKit container.
