# Woven UX redesign

Direction: **quiet luxury meets private photo journal**.

The redesign must preserve the verified security behavior: device-bound keys,
fail-closed authentication, background and capture shielding, explicit Pair
approval, automatic locking, encrypted storage, and revocation. Presentation may
change; those boundaries may not.

## First slice

- Replaced absolute black and bright gold with warm ink, ivory, and muted copper
  semantic tokens.
- Added a restrained woven mark and reusable inset surface.
- Rebuilt production sign-in around the product promise rather than authentication
  mechanics while retaining native Apple and Google controls.
- Replaced separate Solo/Pair tabs with one Vaults home and native push navigation.
- Preserved fail-closed lifecycle behavior by locking on vault exit and locking
  both stores whenever the home leaves the active scene state.
- Moved account details and sign-out into a single account menu.
- Rewrote the Pair setup, invitation, locked, approval, and empty states in human
  language; removed hashes, relay terminology, request IDs, and vault IDs from the
  primary journey.
- Added a visible invitation-copy action.
- Added Pair multi-photo selection with the same 50-item boundary as Solo and
  aggregated unreadable-item feedback.

## Verification

- Staging Simulator build passed.
- The redesigned Vaults home was installed and visually inspected on iPhone 17e,
  iOS 26.4, without opening decrypted media.
- Full Staging result: 13 logical tests passed, 16 device/configuration executions,
  zero failures or skips.
- Staging and Release Xcode static analysis passed.

## Next slices

1. Refine the Solo and Pair galleries, full-screen viewer, import progress, and
   deletion feedback as one consistent photo experience.
2. Turn Pair creation/joining into a guided, resumable step flow with clearer
   handoff and success states.
3. Improve approval notifications and pending-request visibility without exposing
   private metadata.
4. Add UI assertions for the new navigation, accessibility labels, Dynamic Type,
   VoiceOver order, reduced motion, and failure states.
5. Validate the redesigned flow on the physical iPhone and repeat the interim
   one-iPhone-plus-Simulator workflow before formal two-iPhone acceptance.
