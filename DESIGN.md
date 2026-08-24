---
name: Anchor
description: Plan the day, protect the present, and learn what moved it.
colors:
  night-canvas: "#0A0C10"
  night-surface: "#141922"
  night-raised: "#1D2532"
  day-canvas: "#F4F6FA"
  day-surface: "#FFFFFF"
  ink: "#0F172A"
  frost: "#EDF1F7"
  cobalt: "#3B82F6"
  cobalt-deep: "#1D4ED8"
  sky: "#7DD3FC"
  external-coral: "#FB7185"
  internal-violet: "#A78BFA"
  mixed-amber: "#F5B849"
typography:
  display:
    fontFamily: "SF Pro Rounded, SF Pro Display, sans-serif"
    fontWeight: 600
  body:
    fontFamily: "SF Pro Text, sans-serif"
    fontWeight: 400
  label:
    fontFamily: "SF Pro Rounded, SF Pro Text, sans-serif"
    fontWeight: 600
    letterSpacing: "1.1pt"
rounded:
  sm: "8pt"
  md: "14pt"
  lg: "20pt"
  xl: "28pt"
  action: "999pt"
spacing:
  xxs: "4pt"
  xs: "8pt"
  sm: "12pt"
  md: "16pt"
  lg: "24pt"
  xl: "32pt"
  xxl: "48pt"
components:
  button-primary:
    backgroundColor: "{colors.cobalt}"
    textColor: "#FFFFFF"
    typography: "{typography.label}"
    rounded: "{rounded.action}"
    padding: "12pt 24pt"
  card:
    backgroundColor: "{colors.night-surface}"
    textColor: "{colors.frost}"
    rounded: "{rounded.lg}"
    padding: "16pt"
---

# Design System: Anchor

## Overview

**Creative North Star: “The Anchored Day”**

Anchor is a quiet native instrument for moving between intention, action, and
reflection. Its operating surfaces subtract visual competition so the current
block, remaining time, and next honest action stay unmistakable. The focus ring
is the stable anchor; schedules and reviews organize around the same restrained
geometry rather than becoming a dense productivity dashboard.

Original Indulge illustrations appear only where projection and self-recognition
matter: choosing automatic patterns and satisfying alternatives. They are
authored evidence inside Anchor's system, not permission to repaint every screen
or turn operational controls into scene props.

**Key Characteristics:**

- Native navigation and controls across Mac, iPhone, and Watch.
- One cobalt action hierarchy against quiet tonal surfaces.
- Warm colors communicate where a pull came from, never focus itself.
- Large, legible time and present-tense intention before analytics.
- Cinematic behavioral artwork in onboarding, with text carrying equal meaning.

## Colors

Night is the default long-session posture; the light appearance uses the same
hierarchy on cool, low-glare whites.

### Primary

- **Anchor Cobalt** (#3B82F6): the focus ring, selected navigation, and the one
  primary action.
- **Deep Cobalt** (#1D4ED8) and **Open Sky** (#7DD3FC): the ring's travel and
  restrained focus halo, not independent decorative accents.

### Secondary

- **External Coral** (#FB7185): something in the world came to the person.
- **Internal Violet** (#A78BFA): the person moved toward the pull.
- **Mixed Amber** (#F5B849): bodily, environmental, or genuinely mixed causes.

### Neutral

- **Night Canvas** (#0A0C10), **Night Surface** (#141922), and **Night Raised**
  (#1D2532): layered dark-mode fields.
- **Day Canvas** (#F4F6FA), **Day Surface** (#FFFFFF), and **Ink** (#0F172A):
  light-mode equivalents.
- **Frost** (#EDF1F7): primary dark-mode text.

**The Cool Focus, Warm Interruption Rule.** Nothing that breaks or diverts a
session may wear cobalt. Deliberate schedule changes remain neutral until their
cause is known.

## Typography

**Display Font:** SF Pro Rounded with SF Pro Display fallback

**Body Font:** SF Pro Text
**Label Font:** SF Pro Rounded with SF Pro Text fallback

System text styles and Dynamic Type are authoritative. Rounded weight gives the
timer, section titles, and short actions a steady instrument-like character;
body copy remains plain and compact.

### Hierarchy

- **Display:** largeTitle or title, semibold; current intention and major review
  conclusion only.
- **Headline:** title2/title3, semibold; plan sections and causal findings.
- **Body:** body, regular; explanations and reflection.
- **Label:** caption/caption2, semibold, optionally tracked uppercase; short
  metadata such as PLANNED, ACTUAL, and CAME TO YOU.

## Layout

Top-level iPhone sections use the native tab bar; Mac uses a native split view;
Watch retains its purpose-built remote. Content sits on an 4-point spacing
scale, uses a readable central column for focused tasks, and may expand into
side-by-side plan and evidence panes on Mac or iPad. The current block always
precedes historical analysis.

Artwork may occupy a generous upper region in onboarding, followed by an
accessible selection tray. It scales to fit and never pushes the primary action
under a safe area or keyboard. Operational planning uses lists and timelines,
not a gallery of cards.

## Elevation & Depth

Depth is predominantly tonal. A single diffuse shadow may lift the canonical
Card above the canvas; native sheets and bars use system materials. Focus glow
belongs to the active ring or primary action and is not repeated around every
container.

**The One Raised Surface Rule.** Nest content through spacing and dividers before
placing a card inside another card.

## Shapes

Cards use continuous 20-point corners, compact controls use 8- or 14-point
corners, and major actions are capsules. The focus ring remains the signature
circular form. Indulge artwork keeps its authored silhouettes and is clipped
only by its transparent or rectangular asset boundary, not arbitrary UI masks.

## Components

### Buttons

- **Primary:** one full-width cobalt capsule per decision surface with white
  semibold text and at least a 44-point touch target.
- **Quiet:** raised neutral capsule for secondary actions.
- **Transport:** circular controls under the focus ring; only the primary
  transport action may use cobalt.

### Chips

Selection chips use a quiet raised fill and hairline at rest. The selected state
uses the semantic tint at low opacity plus a stronger border. Image-backed
activity selection may use a larger tile, but it retains the same explicit
selected state and textual label.

### Cards / Containers

The shared Card is the only generic raised container: 20-point corners, one
hairline, 16-point default padding, and a restrained ambient shadow.

### Inputs / Fields

Use native text fields, pickers, date controls, toggles, and sheets. Avoid
web-shaped custom inputs. Focus uses the platform tint and keyboard toolbars
provide an explicit Done action where necessary.

### Navigation

Navigation is structural, never an action. iPhone uses two to five native tabs;
Mac uses the same conceptual sections in a sidebar; deeper schedule editing uses
navigation stacks and sheets.

### Focus Ring

The ring owns elapsed or remaining time, active state, and the central current
intention. It remains visually calmer and larger than any surrounding metric.

### Behavioral Artwork Selector

Original Indulge activity art provides recognition before a person names a
pattern. Every tile has a concise accessible label, multi-selection is obvious
without relying on color, and selection never damages or darkens the depicted
person.

## Do's and Don'ts

### Do:

- **Do** keep the current intention and next action more prominent than metrics.
- **Do** use original Indulge art at behavioral decision points where it adds
  recognition or emotional specificity.
- **Do** label unknown causal gaps honestly and preserve evidence provenance.
- **Do** use native controls, Dynamic Type, safe areas, keyboard conventions,
  increased contrast, and Reduce Motion alternatives.

### Don't:

- **Don't** turn the day into an adherence score, streak wall, or moral heat map.
- **Don't** use cobalt for interruptions or scatter multiple filled actions on a
  screen.
- **Don't** repeat cards until every row looks like a dashboard widget.
- **Don't** infer a cause from artwork, profile answers, or model prose alone.
- **Don't** make image comprehension a prerequisite for using the product.
