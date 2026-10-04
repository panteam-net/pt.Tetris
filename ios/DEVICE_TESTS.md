# Device acceptance checks

These are outstanding runtime checks, not a record of completed tests.

## Build and local play

- Build the app and run the pt.TetrisDuel scheme tests on an iPhone and an iPad.
- Try English and Russian app languages; check menus, controls, help and results
  on both devices for clipped text, and verify translated VoiceOver labels.
- With Russian selected, verify the Local Network permission explanation when
  hosting or joining a nearby game for the first time.
- Confirm iPhone shows one board, iPad offers the shared-device duel, and both
  full-size iPad orientations keep the controls and both fields visible.
- Start solo, rotate at both walls and the floor, hold once per piece, soft-drop,
  hard-drop and fill a line. Confirm score and level progression.
- On iPad, have two people hold opposite movement buttons simultaneously. Drop,
  rotate and hold on both panels. Cancelling one finger must not stop the other.
- Check 2-, 3- and 4-line attacks, cancellation, delayed garbage, top-out and draw.
- Test external keyboards, pause during countdown, pause during play, application
  backgrounding, help, haptics toggle, and a cancelled interactive back swipe.
- Check an iPad window resize; use a sufficiently wide window for shared controls.
- Leave a match and confirm animation stops, discovery stops and the device can sleep.

## Two-device nearby play

- Use two physical devices running the same build. Test iPhone–iPhone,
  iPhone–iPad and iPad–iPad where available.
- Allow Local Network permission, host, select the host and explicitly accept.
  Confirm both screens start only after readiness and show the same countdown.
- Decline an invitation, let one expire, then accept a new invitation. A third
  device must not join an occupied room.
- Test a shared local Wi-Fi network, then peer-to-peer Wi-Fi without a router.
  Internet and Bluetooth are not prerequisites for this app's networking design.
- Move and rotate the guest's piece while the host plays. Verify guest input
  controls only seat 2; confirm matching scores, garbage and final result.
- Pause from either device. Background one device and verify the other cannot
  resume while it is unavailable. Return both and resume if still connected.
- Turn off Wi-Fi or leave the app. Confirm the match stops, no false victory is
  awarded and the player can return to the menu to make a fresh connection.
- Request a rematch on one device only; verify it waits. Accept on the other
  and verify a new synchronized round with the existing win tally.
- Deny Local Network permission, then restore it in Settings and retry from a
  new lobby. Confirm the permission failure is understandable.
- Run several complete matches to assess guest latency and snapshot ordering.

Record the device models, OS versions, connection type and results before
distributing a signed build.
