# Blood Glucose Buddy

Rich Presence for Discord: your live Dexcom reading and trend arrow on your Discord profile.

Website: **[bloodglucosebuddy.tanookistudios.com](https://bloodglucosebuddy.tanookistudios.com)** — download, setup steps and every version.

```
Watching Blood Glucose
112 mg/dL ↗
Rising slowly
02:14 elapsed
```

- Lives in the Mac menu bar, shows your number there too, starts at login.
- Number mode, or colored-dot-only mode (In range / High / Low) for people who'd rather not share the number.
- mg/dL or mmol/L. "Watching" or "Playing". Your own high and low lines.
- A reading older than 15 minutes shows as **No reading**, never as a stale number.
- Dexcom password in the macOS Keychain. No account, no server, no analytics.

**Open source, MIT licensed.**

> **Not a medical device.** Never make treatment decisions from Blood Glucose Buddy — use your Dexcom app or receiver. It reads Dexcom's unofficial Share feed, which can stop working without notice. Not affiliated with or endorsed by Dexcom or Discord.

## How it works

- **Dexcom:** Dexcom's official developer API delays data by an hour (three outside the US), so this reads **Dexcom Share** instead — the live feed the Follow app uses — with the user's own login. Share has to be on with at least one follower. Some accounts won't authenticate by email or phone; the app's *Find My Account ID* opens Dexcom's own sign-in page and reads the account ID from the profile page address. Code: `mac/BloodGlucoseBuddy/Core/Dexcom.swift`.
- **Discord:** Rich Presence over the desktop app's local socket (`$TMPDIR/discord-ipc-N`). One shared Discord application ("Blood Glucose", ID `1558184055437004933`) holds the arrow and dot pictures in `assets/`. Setting a *custom status* from code would be a self-bot, which Discord bans, so this doesn't. Code: `mac/BloodGlucoseBuddy/Core/Discord.swift`.
- **What's shown:** `mac/BloodGlucoseBuddy/Core/Presence.swift`.

Users need Discord's **User Settings → Activity Privacy → Share your detected activities with others** turned on.

## Building

Mac app (macOS 15+, Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen)):

```bash
cd mac
xcodegen generate
open BloodGlucoseBuddy.xcodeproj
```

The app is not sandboxed: the Mac sandbox blocks Discord's local socket. Tests cover the Dexcom parsing, the Discord message framing and what gets shown:

```bash
xcodebuild test -project mac/BloodGlucoseBuddy.xcodeproj -scheme BloodGlucoseBuddyTests -destination 'platform=macOS'
```

To build your own signed copy, change `DEVELOPMENT_TEAM` in `mac/project.yml` to your team.

## Releasing

1. Bump `MARKETING_VERSION` in `mac/project.yml` and add notes to the top of `site/versions.json`.
2. `scripts/release-mac.sh` — tests, builds, signs, notarizes and zips into `dist/`.
3. `gh release create v<version> dist/BloodGlucoseBuddy-<version>-mac.zip`
4. `node site/build.mjs --deploy`

## Windows

On the way.

## License

MIT. Made by Maddie at [Tanooki Studios](https://tanookistudios.com).
