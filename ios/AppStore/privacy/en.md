# Privacy Policy — pt.TetrisDuel

**Last updated: October 4, 2026**

[Русская версия](ru.md)

## 1. About this policy

This policy explains how **pt.TetrisDuel** (the “App”) handles information when
you use it on iPhone or iPad. The developer identified on the App's App Store
product page is responsible for the App's processing of information. In this
policy, “we” and “us” refer to that developer.

The App offers solo play, two-player play on one iPad, and nearby multiplayer.
You do not need to create an account or provide an email address, telephone
number, or real name to play.

## 2. Information stored on your device

The App stores the following preferences in its local application storage:

- Your chosen player name. You may use a nickname or the default name.
- Your sound and haptic-feedback preference.

These preferences allow the App to remember your choices between launches. The
App's gameplay code does not upload them to a developer-operated account or
cloud-storage service.

Boards, scores, elapsed time, round results, and match-win counts are held for
the current game screen or session. The App does not save a permanent match
history or maintain an online leaderboard.

## 3. Nearby multiplayer

When you host or join a nearby game, the App uses Apple's Multipeer Connectivity
framework to discover another device and exchange information over a local or
peer-to-peer connection. Nearby play is intended to work over Wi-Fi and does
not require an internet connection or a matchmaking account.

Your chosen player name and connection information can be visible to other
nearby devices during discovery and invitations, before a game starts. The App
also exchanges protocol-version information to check compatibility. Choose a
nickname if you do not want to disclose your real name.

The host must accept an invitation. After connection, the App allows one
opponent and exchanges the information needed for the match, including:

- Board contents, current and upcoming pieces, held pieces, and landing positions.
- Scores, cleared lines, incoming and outgoing attacks, and match results.
- Control inputs, round identifiers, timing, pause and rematch requests,
  connection heartbeats, and whether the other player's app is available.

This match information is exchanged with the connected opponent rather than
through a developer-operated game server. Game sessions are configured to
require encryption. The player name used for discovery should not be treated
as private information visible only inside an encrypted match.

## 4. Firebase Analytics

The App integrates **Google Analytics for Firebase**, provided by Google.
Firebase is initialized at app launch, and the App records an `analytics_test`
event without custom parameters to check the analytics integration.

Depending on SDK, service, and operating-system settings, Analytics can
automatically process:

- An app-instance identifier and device identifiers, such as Apple's identifier
  for vendor (IDFV), for measurement.
- Device model, operating-system version, app version, language, and other
  technical app or SDK information.
- Usage events such as first launch, sessions, screen views, app updates,
  interaction timing, and the App's launch test event.
- General location information derived from network IP addresses. This does
  not require access to Apple's Location Services or GPS coordinates.
- Technical service metadata used to deliver and maintain the SDK's services.

Analytics identifiers are not necessarily anonymous: they can distinguish an
app installation or device over time. The App does not set an account-based
Analytics user ID or attach your player name, board contents, control inputs,
or scores to its custom Analytics event.

Analytics is used to understand app usage and verify measurement. Google
Analytics also supports optional advertising-related features whose operation
depends on project settings, SDK configuration, and Apple's permissions. The
App itself does not display advertisements or request App Tracking Transparency
authorization. An advertising identifier can be available to an SDK only
subject to the applicable operating-system permissions and configuration.

Analytics operates separately from nearby multiplayer. Playing solo or
disabling Local Network permission does not itself disable Analytics. Events
may be queued locally when the device is offline and transmitted later when a
connection is available.

Google's processing is described in these resources:

- [Google Privacy Policy](https://policies.google.com/privacy?hl=en)
- [Privacy and Security in Firebase](https://firebase.google.com/support/privacy)
- [Google Analytics information for Apple platforms](https://support.google.com/analytics/answer/10285841?hl=en)

## 5. Permissions and your choices

The App requests **Local Network** access to discover and connect to another
player. You can refuse or revoke that permission in **Settings → Privacy &
Security → Local Network**. Nearby multiplayer may then be unavailable; solo
play and two-player play on one iPad do not require that permission.

The App does not request access to your contacts, photos, camera, microphone,
or precise location. It does not request a Bluetooth permission.

You can change your player name on the menu screen and change the sound and
haptic-feedback preference using the game's sound control. These controls do
not change Analytics collection. The current App does not provide an in-app
Analytics opt-out switch or an Analytics data-deletion button.

Deleting the App, rather than offloading it, removes its local application
data from that device under the operating system's normal deletion behavior.
Device or cloud backups are subject to your Apple backup settings and may
restore local data if you restore a backup.

## 6. Sharing and processing locations

Information is handled by the following recipients for the purposes described
above:

- Nearby devices involved in discovery, and the opponent you connect to, for
  nearby multiplayer.
- Google and its service providers, for Analytics and related technical
  processing. Google may process data on infrastructure outside your country,
  including in the United States.

If you contact the developer for support or a privacy request, the contact
details and information you choose to include are used to handle that request.
The support service you use may also process the message under its own policy.

Apple independently handles App Store distribution and any diagnostic or
TestFlight information you share through Apple's services. That processing is
governed by [Apple's Privacy Policy](https://www.apple.com/legal/privacy/).

## 7. Retention and deletion

- **Local preferences:** remain until you change them or remove the App's local
  data. Backup copies are governed by your backup settings.
- **Match information:** is used for the active game screen or session and is
  not saved by the App as permanent match history.
- **Analytics:** is retained according to the settings of the App's Google
  Analytics property and Google's applicable service policies. Retention can
  differ for event-level data and aggregated reports. See
  [Google's retention explanation](https://support.google.com/analytics/answer/7667196?hl=en).

Deleting the App does **not** automatically delete Analytics information already
sent to Google. Privacy or deletion requests can be made using the contact
route below. Because the App does not have accounts or associate your player
name with an Analytics user ID, identifying particular Analytics records may
require additional information and may not always be possible.

## 8. Your privacy rights

Depending on the laws applicable to you, you may have rights to request access
to, correction of, deletion of, or a portable copy of your personal information;
to object to or restrict certain processing; or to withdraw consent where
processing is based on consent. You may also be entitled to complain to your
local data-protection authority.

Contact the developer using the route below to make a request. These rights
are subject to applicable law and the ability to identify the relevant data.

## 9. Children

The App does not request your age or date of birth. Parents or guardians with
questions about a child's information, or requests concerning its deletion,
can contact the developer through the route below. Analytics processing is
described in section 4 and is not turned off by the App based on a player's age.

## 10. Changes to this policy

This policy may be updated when the App, its services, or information-handling
practices change. The date at the top identifies the latest revision.

## 11. Contact

For privacy questions or requests, contact the developer through the **App
Support** link on the **pt.TetrisDuel** App Store product page. The developer's
identity and support contact details are provided on that page and its linked
support page.
