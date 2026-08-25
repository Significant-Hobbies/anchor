---
name: Anchor
description: Plan the day, protect the present, and learn what moved it.
colors:
  night-canvas: "#0B0B0C"
  night-surface: "#151515"
  night-raised: "#202020"
  day-canvas: "#F3F1EC"
  day-surface: "#FBFAF7"
  ink: "#171717"
  frost: "#F2F0EA"
  graphite: "#5B5852"
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
    backgroundColor: "{colors.ink}"
    textColor: "{colors.day-surface}"
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

**Creative North Star: “The Drawn Day”**

Anchor is a quiet native instrument drawn by hand. Original black linework gives
planning, focus, habits, and review an unmistakably human point of view, while
the operating interface stays precise: generous white or night space, native SF
typography, hairline structure, one high-contrast ink action, and warm causal marks. The
doodle is the first emotional read; the schedule, current block, and next honest
action remain the first operational read.

Every primary surface may use one purposeful doodle scene, companion, or
annotation from the original Anchor/Indulge visual world. It must explain the
surface's job or current state and then yield to the interface. Cartoons never
become controls, never carry meaning without text, and never multiply into a
decorative gallery.

**Key Characteristics:**

- Mobile-first composition with native navigation and controls across iPhone,
  Mac, and Watch.
- Authored black-line scenes with selective character colour on neutral paper.
- One ink-and-paper action hierarchy against quiet tonal surfaces.
- Warm colors communicate where a pull came from, never focus itself.
- Large, legible time and present-tense intention before analytics.
- Premium finish through cropping, spacing, type, and motion rather than chrome.

## Colors

Night is the product default across Mac, iPhone, and Watch; the light appearance
uses the same hierarchy on warm, low-glare paper. Settings offers Dark, Light,
and System. Explicit Dark or Light choices follow Anchor's private iCloud data;
System intentionally follows each device and may therefore differ.

### Primary

- **Ink** (#171717) on light paper and **Frost** (#F2F0EA) on charcoal: the
  focus ring, selected navigation, and the one primary action.
- **Graphite** (#5B5852): restrained secondary emphasis, never a competing
  brand colour.

### Secondary

- **External Coral** (#FB7185): something in the world came to the person.
- **Internal Violet** (#A78BFA): the person moved toward the pull.
- **Mixed Amber** (#F5B849): bodily, environmental, or genuinely mixed causes.

### Neutral

- **Night Canvas** (#0B0B0C), **Night Surface** (#151515), and **Night Raised**
  (#202020): layered dark-mode fields.
- **Day Canvas** (#F3F1EC), **Day Surface** (#FBFAF7), and **Ink** (#171717):
  light-mode equivalents.
- **Frost** (#EDF1F7): primary dark-mode text.

**The Quiet Focus, Warm Interruption Rule.** Focus stays neutral and
high-contrast. Coral, violet, and amber are reserved for known interruption
origins; deliberate schedule changes remain neutral until their cause is known.

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

Top-level iPhone sections use the native tab bar and define the product's core
hierarchy; Mac expands the same model through Anchor's authored navigation rail;
Watch retains its purpose-built remote. The Mac rail collapses to icons below
840 points, carries labels through standard windows, and opens the workspace to
a wider reading column at 1200 points. Content sits on a 4-point spacing scale, uses a
readable central column for focused tasks, and may expand into side-by-side plan
and evidence panes on Mac or iPad. The current block always precedes historical
analysis.

One doodle scene may occupy a generous upper region, become a compact companion,
or reduce to a hand-drawn annotation as density rises. It collapses after the
first scroll on dense operational screens and never pushes the primary action
under a safe area or keyboard. Planning uses clean timelines and rows, not a
gallery of illustrated cards.

## Elevation & Depth

Depth is predominantly tonal. White space, crop, and line weight create the
premium hierarchy; a single diffuse shadow may lift the current block or the
canonical Card above the canvas. Native sheets and bars use system materials.
Focus glow belongs to the active ring or primary action and is not repeated
around illustrations or every container.

**The One Raised Surface Rule.** Nest content through spacing and dividers before
placing a card inside another card.

## Shapes

Cards use continuous 20-point corners, compact controls use 8- or 14-point
corners, and major actions are capsules. The focus ring remains the signature
circular form. Indulge artwork keeps its authored silhouettes and is clipped
only by its transparent or rectangular asset boundary, not arbitrary UI masks.

## Components

### Buttons

- **Primary:** one full-width ink/paper capsule per decision surface with
  reversed semibold text and at least a 44-point touch target. A restrained
  three-point lower edge gives the control physical presence; hover lifts the
  face and press settles it instead of shrinking it.
- **Quiet:** the same capsule geometry and press physics at lower contrast so
  secondary actions feel intentional without competing with the decision.
- **Transport:** circular controls under the focus ring use the same shallow
  edge and settle interaction; only the primary transport action receives the
  full high-contrast treatment.
- **Motion:** Reduce Motion removes the hover and press transitions while
  preserving hierarchy, depth, and touch targets.

### Chips

Selection chips use a quiet raised fill and hairline at rest. The selected state
uses the semantic tint at low opacity plus a stronger border. Image-backed
activity selection may use a larger tile, but it retains the same explicit
selected state and textual label.

### Cards / Containers

The shared Card is the only generic raised container: 20-point corners, one
hairline, 16-point default padding, and a restrained ambient shadow.

Settings use `PreferenceGroup`, `PreferenceActionRow`, and `PreferenceInfoRow`
instead of one card per fact. Wide workspaces compose those same state-free
groups in two columns; compact Mac and iPhone stack them without a second screen
implementation.

### Significant Hobbies family boundary

The family may share neutral mechanics: semantic theme roles, spacing, radii,
button physics, preference rows, responsive containers, art-placement scaffolds,
and Reduce Motion policy. It must not share Anchor's product voice wholesale.
Anchor's doodles, focus ring, day rail, interruption knot, planned-versus-lived
trace, copy, and information architecture stay in Anchor. Each sibling supplies
its own authored artwork and domain meaning through the shared mechanics.

### Inputs / Fields

Use native text fields, pickers, date controls, toggles, and sheets. Avoid
web-shaped custom inputs. Focus uses the platform tint and keyboard toolbars
provide an explicit Done action where necessary.

### Navigation

Navigation is structural, never an action. iPhone uses two to five native tabs;
Mac uses the same conceptual sections in a custom rail rather than the stock
sidebar; deeper schedule editing uses navigation stacks and sheets.

### Focus Ring

The ring owns elapsed or remaining time, active state, and the central current
intention. It remains visually calmer and larger than any surrounding metric.

### Behavioral Artwork Selector

Authored Anchor scenes provide recognition before a person names a pattern.
Every choice gets its own narrative action rather than a repeated person-plus-
symbol template. Transparent sprites sit naturally on the selector surface;
every tile has a concise accessible label, and selection never relies on colour.

### Doodle Scene

One authored line illustration introduces the job or state of a primary surface.
It is transparent, edge-free artwork that sits directly on the app canvas and
ships with light/dark linework where needed; never place a doodle inside a
generic image card or ship a baked background. Interface chrome remains neutral;
coral, violet, and amber may encode interruption origin. On iPhone it
may occupy roughly one fifth of the first viewport before collapsing into a
compact companion; Mac may place the same scene beside, never above, the working
schedule. Text states the meaning independently.

## Do's and Don'ts

### Do:

- **Do** keep the current intention and next action more prominent than metrics.
- **Do** lead every primary surface with one purposeful illustration, companion,
  or annotation from the original Anchor/Indulge line-art world.
- **Do** make doodles feel premium through deliberate crops, stable line weight,
  quiet native typography, and generous negative space.
- **Do** verify a raster asset has a real alpha channel or supply transparent
  light/dark vectors before it enters a primary surface.
- **Do** label unknown causal gaps honestly and preserve evidence provenance.
- **Do** use native controls, Dynamic Type, safe areas, keyboard conventions,
  increased contrast, and Reduce Motion alternatives.

### Don't:

- **Don't** turn the day into an adherence score, streak wall, or moral heat map.
- **Don't** tint the app blue or scatter multiple filled actions on a screen.
- **Don't** repeat cards until every row looks like a dashboard widget.
- **Don't** scatter multiple cartoons across one operating screen or turn a
  doodle into a button, status badge, or substitute for data.
- **Don't** frame a doodle in a card to hide a baked background or rough edge.
- **Don't** infer a cause from artwork, profile answers, or model prose alone.
- **Don't** make image comprehension a prerequisite for using the product.
