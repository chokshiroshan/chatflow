# Brand Approval

## Status

Approved provisionally for unattended Maquette workflow.

## Approved Source

- `.maquette/brand/brand-board-v2.png`

## Decision Notes

- The user asked to shift the direction toward OpenAI-adjacent design: calm, precise, demo-led, and research-product-like.
- The board keeps the project clearly third-party with "unofficial / built outside the building" language and avoids OpenAI logos, knot marks, official wordmarks, and copied product lockups.
- The first generated board, `.maquette/brand/brand-board-v1.png`, is retained as historical context but superseded because it was too terminal-zine heavy for the revised direction.

## Token Status

- `.maquette/brand/design-system.json` was updated from the inspected v2 board.
- `.maquette/brand/tokens.css` was exported from the board-derived design-system JSON.

## Design Summary

- Palette: warm paper, black ink, fog and trace neutrals, restrained signal green, caution rust.
- Typography: editorial sans direction using Geist/IBM Plex Sans/Space Grotesk fallbacks, with JetBrains Mono for auth and realtime proof surfaces.
- Surfaces: matte paper panels, quiet shadows, precise hairlines, and subtle grid structure.
- Interaction: high-contrast focus rings, subtle hover elevation, clear disabled/error/selected states.

## Guardrails

- Do not imply the page is official OpenAI software.
- Do not use OpenAI marks or copied official layouts.
- Keep OAuth, token exchange, and realtime inference details visible.
