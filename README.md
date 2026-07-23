# NeoFreeBird for X 12.9

This fork combines BHTwitter's X 12.9 compatibility work with NeoFreeBird's
newer modular architecture. It is currently a beta intended for testing against
X 12.9.

## Highlights

- Layered ad blocking for Home, profiles, search, conversations, Explore,
  cards, articles, and video ad paths.
- Highest-quality photo loading, optional full-frame timeline media, and a
  highest-video preference.
- Modern video/GIF downloads across X 12.9's timeline, carousel, player-menu,
  overflow-menu, and supported Direct Message paths.
- Native tab reordering plus an independent, movable **My Likes** bottom
  destination that can sit alongside Grok, with normal in-tab navigation and
  swipe-back.
- Appearance editors for the bottom bar, the Likes section, and X 12.9's
  sidebar, with tap-to-hide tiles and drag reordering.
- A Posts/Media view for Likes with a pinch-adjustable waterfall gallery,
  newest-first loading, continuous pagination, original-quality photo viewing,
  and highest-available MP4 playback.
- Updated profile, search, Grok, timeline, confirmation, appearance, branding,
  custom-font, and accessibility-related features.
- A runtime compatibility report that can be shared from the Debug settings.

Beta 11 retargets X 12.9's separate video/carousel views, repairs GIF
conversion, applies sidebar changes through its observable Swift data-source
setters, and removes the first-open Likes loading cover.

Every new X 12.9 behavior has a setting; custom navigation is controlled from
its editor. Compatibility shims preserve native behavior when their option is
off.

The full per-feature review is in
[`docs/X12_9_FEATURE_AUDIT.md`](docs/X12_9_FEATURE_AUDIT.md).

## Important login note

X may reject modified clients through server/app attestation. This project does
not bypass attestation and does not include replacement login flows, cookie or
session-token harvesting, or subscription-state spoofing. Those approaches are
fragile, unsafe for accounts, and outside this fork's compatibility work.

## Build locally

Install [Theos](https://github.com/theos/theos) and
[cyan](https://github.com/asdfzxcvbn/pyzule-rw) for IPA/TrollStore output, then:

```bash
git clone --recursive https://github.com/Vicitiniman/BHTwitter.git
cd BHTwitter
chmod +x build.sh
```

Place a decrypted IPA at `packages/com.atebits.Tweetie2.ipa` for IPA builds and
run one of:

```bash
./build.sh --sideloaded
./build.sh --trollstore
./build.sh --rootless
./build.sh --rootfull
```

The FFmpeg stack is built from source on first use and reused afterward.

## Build with GitHub Actions

Run **Build NeoFreeBird** from the Actions tab. Select a deployment format and,
for sideloaded/TrollStore builds, provide a direct URL to a decrypted IPA you
are authorized to use. The workflow checks out the selected branch/commit and
its submodules, so fork changes are included in the build.

## Test logs

After installing a test build:

1. Open `Settings > NeoFreeBird > Debug`.
2. Tap **Export compatibility report**.
3. Attach the resulting JSON to the GitHub issue or pull request.

The same report is stored inside the app container at
`Library/Caches/BHTwitter-X12.9-Compatibility.json`. It contains app/build and
hook-availability information, not account credentials.

## Credits

Built on the work of BHTwitter and NeoFreeBird contributors, with selected
targeted improvements reviewed from Theacrat's and Orion's NeoFreeBird branches.
