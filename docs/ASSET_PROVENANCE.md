# Asset provenance

## Anchor originals

- `Apps/Shared/Assets.xcassets/AnchorOnboarding.imageset/` is Anchor's original
  interruption-first onboarding illustration, generated specifically for Anchor
  with OpenAI's built-in image-generation tool.

## Indulge material carried into Anchor

The owner explicitly approved bringing the strongest behavioral onboarding
material from Indulge/Habits into the merged Anchor product. This record is
self-contained so Anchor does not depend on an Indulge checkout for provenance.

- `Apps/Shared/Assets.xcassets/HabitsOnboarding.imageset/` is the original
  Habits onboarding hero copied without visual modification.
- `Apps/Shared/Assets.xcassets/Pattern-*.imageset/` contains the complete set of
  24 original generated Indulge activity-selector artworks.
- `Apps/Shared/Assets.xcassets/Direction-*.imageset/` contains the eight original
  generated Indulge desired-life artworks.

The source assets were generated specifically for Indulge with OpenAI's built-in
image-generation tool. They are original project assets, not marketplace
downloads or screenshots of third-party applications. Anchor copies them
locally so the merged onboarding remains deterministic, offline, and free of
runtime image-generation or network requirements.

SwiftUI supplies selection state, copy, accessibility labels, Dynamic Type,
Reduce Motion behavior, and transitions. Artwork is never the only carrier of
meaning. Record any later imported source with its author, source, license,
attribution requirements, modifications, and final repository path.
