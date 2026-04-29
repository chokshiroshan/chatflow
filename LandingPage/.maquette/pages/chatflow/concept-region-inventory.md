# ChatFlow Page Concept Region Inventory

## Concept Source

- `.maquette/pages/chatflow/concept.png`

## Regions

- Header/nav: implemented. Compact OpenAI-adjacent header with brand, low-friction section links, desktop actions, and tablet/mobile collapsed-open states.
- Hero copy: implemented. Product-first headline focused on the dictation loop rather than the auth trick, with ChatGPT-plan framing and third-party disclosure.
- Hero product preview: implemented closely. Large staged macOS-style preview with floating dictation pill, editor window, and enhanced-mode toggle.
- Proof cards: implemented with adaptation. The concept shows compact proof panels immediately under the hero; the coded page keeps the proof in the dedicated `receipts` section for better reading rhythm on the real page.
- Feature grid: implemented. Four cards covering hotkey loop, enhanced mode, app injection, and ChatGPT-plan billing path.
- Enhanced-mode explainer: implemented. Three-step context pipeline plus a side note about technical vocabulary and on-demand capture.
- Quick start: implemented. Three install paths: DMG, Homebrew, and source.
- Disclaimer / CYA: implemented. Third-party and unaffiliated language preserved.
- Footer CTA: implemented. Builder-oriented closing CTA with GitHub-friendly actions.
- Responsive navigation callouts: implemented behaviorally rather than visually. The concept shows separate tablet/mobile nav callouts; the code implements the actual drawer and records responsive screenshots instead of rendering those callouts in-page.

## Component Coverage

- Header/nav uses the existing responsive navigation pattern.
- Hero preview uses custom page composition built from existing button/chip/surface primitives.
- Feature, proof, install, disclaimer, and footer areas reuse the card and CTA component families already established in `.maquette/components/`.
- Mobile navigation uses the existing toggle/drawer behavior validated by the responsive audit.
