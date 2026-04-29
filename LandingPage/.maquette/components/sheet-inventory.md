# Component Sheet Inventory

## Core Primitives

- Source: `.maquette/components/component-sheet-core-primitives-css-contract-v1.png`
- Contract: `.maquette/components/contracts/core-primitives.contract.css`
- Families: buttons, button icons, kickers, chips, status dots, inline links.
- States: hover, active, focus-visible, disabled.
- Decision: implemented and reviewed.
- Notes: raw poster colors normalized to v2 design-system tokens.

## Navigation Layout

- Source: `.maquette/components/component-sheet-navigation-layout-css-contract-v1.png`
- Contract: `.maquette/components/contracts/navigation-layout.contract.css`
- Families: responsive primary nav, brand text block, plain mark, links, action area, mobile toggle, mobile panel, layout shell, layout grid.
- States: hover, focus-visible, active/current link, compact open panel.
- Decision: implemented and reviewed.
- Notes: image-gen token spelling imperfections were corrected in transcription. Breakpoint was widened to 1024px after audit expected compact navigation at that width.

## Cards Composites

- Source: `.maquette/components/component-sheet-cards-composites-css-contract-v1.png`
- Contract: `.maquette/components/contracts/cards-composites.contract.css`
- Families: proof panels, code panels, equal-height flow cards, waveform, quickstart rows, disclaimer card, footer CTA.
- States: hover, focus-within, inverse, signal, caution, reduced-motion waveform.
- Decision: implemented and reviewed.
- Notes: image-worker hit usage limit, so this poster was generated in the main workflow and copied into the project. Card sizing was corrected to border-box after screenshot inspection.
