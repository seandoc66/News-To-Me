# Troubleshooting — the app on the phone

**This document is for whoever is debugging next, human or agent.** Each entry is
a failure that actually happened, what was checked, and — just as important —
which plausible explanations turned out to be wrong. The dead ends are the
point: they are where the hours went.

For how the system fits together, see [`ARCHITECTURE.md`](ARCHITECTURE.md). For
the install mechanics, see [`scripts/install-to-phone.sh`](scripts/install-to-phone.sh).

---

## Fixed reference — the signing setup

Check these against reality before trusting anything below; they are facts as of
2026-09-10, not laws.

| Thing | Value |
| --- | --- |
| Team | `7UPTF38D36` — **paid** Apple Developer Program, not a personal team |
| Bundle ID | `com.shanedoc.NewsApp` |
| Signing cert | `Apple Development: Shane Doherty (VGZBK3VJH2)`, expires **2027-07-31** |
| Profile | `iOS Team Provisioning Profile: *` (wildcard), UUID `1e018321-…`, expires **2027-07-31** |
| Phone | iPhone SE 3rd gen, UDID `00008110-001C19121A51A01E` |
| CoreDevice id | `0B9CB8D0-D766-5309-9ABA-1B1B43B9CDB7` (differs from the UDID — both are needed) |

Because the team is **paid**, profiles last a year, not seven days. Two things
follow, and both misled the 2026-09-10 investigation:

- There is no weekly re-install. If the app dies after a couple of weeks,
  expiry is not the reason.
- **Settings → General → VPN & Device Management is empty, and that is
  correct.** The "Developer App → Trust" entry only ever appears for free
  personal-team signing. Its absence is not evidence of anything.

---

## 2026-09-10 — "App Unavailable", then installs rejected too

### Symptoms

- App had run fine for ~10 days with no development activity, then stopped.
  Tapping the icon gave an unavailable message. No iOS upgrade had happened.
- Icon looked **normal** (not greyed, no cloud badge), with iOS's blue
  "recently installed" dot beside the name.
- Launching the installed build 8 from the Mac:

  ```
  FBSOpenApplicationServiceErrorDomain error 1 — RequestDenied
  Unable to launch com.shanedoc.NewsApp because it has an invalid code
  signature, inadequate entitlements or its profile has not been explicitly
  trusted by the user.
  ```

- Installing a freshly built, freshly signed build:

  ```
  0xe8008015 (A valid provisioning profile for this executable was not found.)
  MIInstallerErrorDomain error 13 — ApplicationVerificationFailed
  ```

### Resolution

**Rebooting the phone fixed it.** The existing build 8 launched normally
afterwards. Nothing on the Mac was changed, and no reinstall was needed — the
app on the phone is still build 8.

### Root cause

iOS keeps installed provisioning profiles in a registry that `amfid` (the
code-signing authority) consults through an in-memory cache. **One cache serves
both launching and installing**, which is why both broke at the same moment and
why both recovered together. A reboot rebuilds it from disk.

Everything durable was verified intact and unchanged across the reboot — bundle,
embedded profile, certificate, developer account. Only volatile state was
cleared. That places the fault in the cache with high confidence.

**The trigger is unconfirmed.** A jetsam kill or crash of the daemon under
memory pressure fits the evidence and fits "suddenly, on a day nobody touched
it", but it was not observed. Do not present it as established.

### Ruled out — do not re-check these first

Every row was verified on 2026-09-10 and was **not** the cause.

| Theory | How it was ruled out |
| --- | --- |
| 7-day free-profile expiry | Paid team; profile ran to 2027-07-31. The claim came from a stale comment in the install script, since corrected. |
| Certificate expired | `openssl x509 -noout -dates` → valid to 2027-07-31 |
| Certificate revoked or auto-renewed away | Apple OCSP (`ocsp.apple.com/ocsp03-wwdrg304`) returned `Cert Status: good` that morning |
| Profile expired | Decoded profile → expires 2027-07-31 |
| Device missing from profile | UDID present in the profile's `ProvisionedDevices` |
| Signing cert missing from profile | Profile carried 2 certs; the signing serial `17076606…` was one of them |
| iOS offloaded the app | `devicectl device info apps` showed it still installed as build 8; icon was normal |
| Entitlement mismatch | App requested only `application-identifier`, `team-identifier`, `get-task-allow` — all covered by the wildcard profile |
| Deployment target vs iOS | App min 18.0, phone on 18.6.2 |
| Developer Mode off | `developerModeStatus = enabled` |
| Corrupt build output | `codesign -vvv --deep --strict` → valid on disk, satisfies its designated requirement |
| Missing "Trust" in VPN & Device Management | That entry never appears for paid teams (see above) |

### Fast triage if it recurs

Reboot the phone first — it is 60 seconds and it is what worked. If it comes
back, or you want the cause rather than the cure, **capture the log before
rebooting** (see below), then work down this list.

```bash
# 1. Is the app even still installed, and as which build?
xcrun devicectl device info apps --device 0B9CB8D0-D766-5309-9ABA-1B1B43B9CDB7 \
    --json-output /tmp/apps.json

# 2. Cert dates
security find-certificate -c "Apple Development: Shane Doherty" -p \
    | openssl x509 -noout -dates

# 3. Profile expiry
security cms -D -i ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision \
    | plutil -extract ExpirationDate raw -

# 4. Is the cert revoked? (needs the WWDR G3 issuer in issuer.pem)
openssl ocsp -issuer issuer.pem -cert leaf.pem \
    -url http://ocsp.apple.com/ocsp03-wwdrg304 -header "Host=ocsp.apple.com" -noverify

# 5. What the built app actually claims
codesign -dvvv build/phone/Build/Products/Release-iphoneos/NewsApp.app
codesign -d --entitlements :- build/phone/Build/Products/Release-iphoneos/NewsApp.app
```

### Getting real evidence next time

This investigation reasoned backwards from error codes because no device log was
captured. That gap is now closed — `libimobiledevice` was installed on the Mac
on 2026-09-10:

```bash
idevicesyslog | grep -iE 'amfid|installd|MIInstaller'
```

Run that while reproducing the failure. `amfid` states its actual reason for
rejecting a signature, which is the one thing never obtained on the day.

Two traps worth knowing:

- **`log stream --device-udid` no longer exists.** macOS 26 removed device
  support from `log`. This is why `idevicesyslog` is needed at all.
- `idevicesyslog` is very chatty — ~47,000 lines in six seconds. Always filter.

The phone's unified log **survives reboots**, so if the app is rebooted before
anyone thinks to capture anything, `xcrun devicectl device sysdiagnose` can
still recover the earlier `amfid` entries. It takes minutes, produces a few
hundred MB, and sweeps up unrelated personal data from the phone — ask Shane
before running it.

### Footnote

The failed install attempts bumped `.git/build-number` to 10 while the phone
kept running build 8, so the next install lands as build 11. Harmless; the
counter only needs to make two installs distinguishable.
