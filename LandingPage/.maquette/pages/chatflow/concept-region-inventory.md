# ChatFlow Page Concept Region Inventory

## Concept Source

- `.maquette/pages/chatflow/concept.png`

## Regions

- Header/nav: implemented. Sticky plain text identity, unofficial note, desktop links/actions, tablet/mobile collapsed toggle and stacked panel.
- Hero copy: implemented. Large editorial headline, direct OAuth/token/realtime subhead, casual CTAs, built-outside-the-building chip.
- Hero proof/demo: implemented. Token trace panel and inverse realtime stream panel with waveform/event lines.
- Responsive nav callout: implemented differently with reason. The concept shows side annotations; the code implements the actual responsive nav behavior and records open-state screenshots rather than showing separate phone mockups in the final page.
- The Trick: implemented. Three connected flow cards for OAuth, token exchange, realtime inference.
- Why interesting: implemented. Four compact cards for no API key, works today, fast demos, likely shelf life, plus a caution note.
- Quick Start: implemented. Three command rows, copy labels, compact side note.
- Disclaimer / CYA: implemented. Independent project, not affiliated, research/learning artifact, use responsibly.
- Footer CTA: implemented. Star/read/ship-small actions with receipt-oriented copy.
- Raster imagery: intentionally omitted with reason. The concept uses only UI surfaces, diagrams, and simple annotations; no product photos or generated hero imagery are required.

## Component Coverage

- Header/nav uses `ResponsiveNav`.
- Hero CTAs and labels use `Button`, `Proof Label Primitives`.
- Proof/demo uses `ProofPanel`, `waveform`, and code panel primitives.
- The Trick and Why cards use `FlowCard`.
- Quick Start uses `quickstart` and `quickstart__command`.
- CYA uses `disclaimer-card`.
- Footer uses `footer-cta`.
