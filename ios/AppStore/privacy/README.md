# Privacy policies

- [English](en.md)
- [Русский](ru.md)

The policies cover the current iPhone/iPad app: local player-name and feedback
preferences, nearby-device discovery and encrypted match sessions, Firebase
Analytics, permissions, retention, deletion, and privacy requests. Both versions
carry the same revision date and the same substantive information.

## Publishing

Publish each Markdown document as a publicly accessible, readable HTTPS page,
with working links between languages. Use the corresponding published URL in
App Store Connect's **Privacy Policy URL** field. Adding the Markdown files to
the repository does not publish a website or populate that field automatically.

The contact section uses the publisher identity and **App Support** contact on
the App Store product page. Keep that route current and usable for privacy
requests. If you prefer a direct contact address, add your publisher name and
privacy email consistently to both versions.

The exact Analytics retention period, data-sharing options, Google signals, and
advertising-account integrations are configured outside this repository in
Firebase/Google Analytics. Check the production project's settings when
publishing; the policies do not invent a retention period or an in-app opt-out.

## Implementation references

- `TetrisDuel/App/AppDelegate.swift`: Firebase initialization and the
  `analytics_test` event without custom parameters.
- `TetrisDuel/Modules/Menu/MenuVIPER.swift`: local `playerName` preference.
- `TetrisDuel/Services/FeedbackService.swift`: local `feedbackMuted` preference.
- `TetrisDuel/Services/MultipeerTransport.swift`: names and compatibility data
  during discovery, host-approved invitations, one opponent, required session encryption.
- `TetrisDuel/Core/WireProtocol.swift`: transmitted match state and controls.
- `TetrisDuel/Modules/Game/GameInteractor.swift`: in-memory match state.
- `TetrisDuel/Resources/Info.plist`: Local Network permission and supported platforms.

Paths above are relative to `ios/`.

The app links Firebase Analytics and initializes it at launch. The
`IS_ANALYTICS_ENABLED` value in `GoogleService-Info.plist` is not used by the
app's code as a user-facing privacy control. Google's documented collection
controls (`FIREBASE_ANALYTICS_COLLECTION_ENABLED`,
`FIREBASE_ANALYTICS_COLLECTION_DEACTIVATED`, and `setAnalyticsCollectionEnabled`)
are not configured by the current app.

Reference documentation:

- [Google Analytics data collection on Apple platforms](https://support.google.com/analytics/answer/10285841?hl=en)
- [Configure Analytics data collection and usage](https://firebase.google.com/docs/analytics/configure-data-collection)
- [Privacy and Security in Firebase](https://firebase.google.com/support/privacy)
