# On This Day • Photo Sweeper: teardown and build plan

Target: App Store id 6752840632, "On This Day • Photo Sweeper", by OmarKnows LLC.
Research date: 2026-09-08. Listing verified on device the same day.

Related: [similar-apps.md](similar-apps.md) puts 32 similar apps and the two native Photos apps
in one feature matrix with the unmet needs from reviews. [product-spec.md](product-spec.md) defines what we build.

## Verdict

The app is a small, well-built, honest entry in a crowded template: show the user photos taken on
today's date in past years, let them swipe to keep or delete, count the storage saved, and sell an
upgrade. At least fifteen apps ship that loop. Two of them matter more than the target. Swipewipe
owns the category by volume and charges the most. This Day (Raymond Kim) owns the "one day at a
time" framing with the indie press and charges a fair price.

The target is a side project by Omar Shahine, a Microsoft corporate vice president who started
building iPhone apps with AI tools in September 2025 and has shipped five since. It has four
ratings after a year. It also already does several things we planned as differentiators: pending
deletion with undo, share a memory with date and place, create an album from the day, favorites,
widgets, streaks, and a strict on-device privacy stance. Copying it gains nothing.

The opening is still real. Three structural weaknesses run through the whole category and this
app shares them: empty days, a feed with no context beyond the date, and delete as the only
outcome. The target adds a fourth of its own: the free tier ends after seven reviewed days, which
is the exact moment a daily habit is forming, and the lifetime price is three times the yearly.
Our version wins on those four, keeps the daily ritual free forever, and gets the name and the
store listing right where this one did not.

## What we verified, and what we did not

Verified on device from the App Store listing on 2026-09-08, and from the developer's own site and
newsletter as indexed by search engines:

| Field | Value |
|---|---|
| Name and subtitle | On This Day • Photo Sweeper. "Tidy the past to spark joy" |
| Developer | OmarKnows LLC, Omar Shahine. Site: omarknows.app/on-this-day |
| Category, age rating | Photo & Video, 4+ |
| Ratings | 4 ratings, 5.0 average. One visible review thanks the developer by first name |
| Current version | 1.1.3, shipped about a month before this research. Added "Group by Year" |
| Launch | Privacy policy effective 2025-09-01. The developer dates his first app to September 2025 |
| Platform | Built for iOS 26. iPad and Mac support not stated |
| Free tier | Everything, until the user has reviewed seven days |
| Paid | $1.99 a month, $19.99 a year, $59.99 lifetime. Unlocks unlimited days, widgets, custom icons |
| Privacy label claims | On-device only, zero telemetry, no analytics, no accounts, no uploads, no ads |

Not verified: download or revenue estimates (no app-intelligence site indexes it), whether it
runs on iPad, localization, the exact version history dates, and how the triage screen behaves
beyond what the store screenshots show. The developer's newsletter post about his first year of
apps was not reachable in full, so any numbers in it are unknown.

Facts about its footprint:

- The only page any search engine had indexed for the app itself was the Japanese storefront's
  "customers also bought" page. No press, no Reddit, no TikTok, no Product Hunt. Distribution is
  the developer's own newsletter, Threads, and X audience.
- The name collides with PhotoSweeper, a Mac duplicate finder sold since 2011 by Overmacs, and
  with PhotoSweeper Mobile (2024). Every search for the target's name returns those apps first.
- The subtitle spends its 30 characters on a Marie Kondo reference with no search keyword in it.

## What the app does (verified)

From the listing text and screenshots.

Daily memory resurfacing.

- Photos and videos taken on today's date across past years, grouped by year, newest first.
- Swipe to keep or delete. Undo anytime. Deletion happens at the end of the session, with a
  "real storage-saved" count.
- Inline video playback and Live Photo autoplay.
- Share a memory with its date and location, formatted for texts and stories.
- Create an album from the day in Apple Photos. Favorite. View full metadata in place.
- Browse any date with a date picker.

Library upkeep. The listing says "reduce clutter and duplicates" and "clear out screenshots and
throwaways", but it names no detection feature, so read that as marketing for the swipe flow.

Habit. Streak stats, reclaimed-space total, optional daily reminder.

Widgets. Small, medium, and large Home Screen widgets that show the day's memories and the streak
and open the review. Paid only.

Privacy. All processing on device, no accounts, no uploads, no analytics, no ads.

The store screenshot shows a grid of the day's photos ("April 26, 50 Photos") with a filter
control, not a card stack, so the triage view is probably a grid you tap into rather than a
Tinder-style deck.

## What the app does not do

Specific to the target, from its own listing:

1. No automatic fallback on an empty day. The date picker lets the user hunt for one by hand.
2. No grouping below the year. No moments, no place names, even though it already reads
   location for sharing.
3. No maybe pile. Keep or delete, then the session ends.
4. No near-duplicate or burst detection, and no Live Photo or video compression.
5. No mention of iCloud Shared Photo Library or shared albums.
6. iPad and Mac are not stated in the listing, and no sync of review state across devices.
7. Widgets are display-only and paid. No interactive widget, Lock Screen widget, Watch, or
   Shortcuts.
8. The free tier is a seven-day trial by another name. After seven reviewed days the daily
   ritual itself is paywalled.

Shared with the whole category, from reviews and comparison articles across Swipewipe, Cleanup,
Slidebox, This Day, Favvy, Clever Cleaner, LuminaClean, Odays, and the memory-viewer apps:

9. Weekly billing at the publisher-owned apps. Swipewipe's paywall shows $8.99 to $9.99 a week
   and Cleanup shows $4.99 to $11.99 a week depending on the source. Users describe the
   trial-to-charge flow as a trap. The target avoids this, to its credit.
10. Privacy fear. Swipewipe's privacy policy says photos may be uploaded. The free apps and the
    target all lead with "on device" because it sells.
11. Crashes on bulk delete. Multiple Swipewipe reviews report crashes near 4,000 items.
12. Delete is the only exit for a good memory. Timehop proved that sharing is the retention
    loop. The target has share and album creation, which is more than most cleaners.

## The goal

Two jobs fused into one habit.

- The nostalgia hit. Facebook's On This Day, Timehop, and Google Photos' "Rediscover this day"
  (2015) trained a decade of users to expect a daily memory. Apple Photos has Memories and a
  Featured Photos widget but no explicit "on this day" surface, so the gap is real on iPhone.
- The storage chore. "iPhone storage full" is evergreen search demand. Cleaners monetize the
  anxiety.

The fusion is the insight. Nostalgia makes the chore pleasant, which makes it daily, which makes
a paid tier defensible. The target's own tagline says it: "one day, one memory, one swipe at a
time." Its goal is modest and personal. It was the developer's first app, built for his own
library, with a no-account, no-ads, no-tracking ethos he applies to all five of his apps. This
Day made the same bet a few months later with a clearer free tier and got the 9to5Mac Indie App
Spotlight for it.

## Pricing landscape

| App | Free tier | Paid | Notes |
|---|---|---|---|
| On This Day • Photo Sweeper (target) | Full app until seven days are reviewed | $1.99 a month, $19.99 a year, $59.99 lifetime | 4 ratings, 5.0. Widgets and icons paid only |
| Swipewipe (MWM) | Limited swipes, ads | $8.99 to $9.99 a week, $109.99 a year. Older reviews cite $24 to $40 a year | 3-day trial. 4.7 stars, 84K US ratings. Sensor Tower estimated 400K downloads and $1M revenue in one month (early 2026). 1M+ MAU. Acquired by MWM June 2024 |
| Cleanup (BPMobile) | Trial into weekly | $4.99 to $11.99 a week by source, $44.99 lifetime | Around 600K ratings. Auto-enrolls into weekly after trial |
| CleanMy Phone (MacPaw) | 3-day trial | About $7.99 a month, $19.99 a year on promotion | Most polished automated cleaner |
| Slidebox (MWM) | Basic sorting | $4.99 a month, $49.99 a year, lifetime tier | Editors' Choice. Swipe up to trash, tap to file into an album |
| This Day (Raymond Kim) | Daily review free | $3.99 a month, $29.99 a year | 7-day trial on annual. iOS 26 only. Premium adds filters, unlimited duplicates, unlimited Live Photo conversion, icons |
| On This Day (Florian Grossmann) | Last three years free | $4.99 one-time or $0.99 a month | Viewer only. MacStories review |
| Odays | Daily review free | Monthly, yearly, and lifetime (prices not indexed) | Product Hunt launch |
| LuminaClean | 65 deletes, then 10 a day | $17.99 lifetime, $5 a month | On-device AI, no uploads |
| Favvy | 100 swipes a day, earn more | Pro lifts the cap | No account, no trial wall |
| Clever Cleaner (CleverFiles) | Unlimited swiping, no ads | Daily caps on extra tools since 2026 | Reviewers' pick for "genuinely free" |
| Swipe Clean | 3-day trial | $4.99 a week or $19.99 a year | |
| Quick Sweep | Free | $4.99, $19.99, $29.99 one-time tiers | |
| Memories: Relive Your Photos | Everything free | None | Viewer |

Two pricing worlds. The publisher-owned apps (MWM, BPMobile, MacPaw) charge $5 to $12 a week and
buy the users back with TikTok ads. The indies charge $2 to $30 a year or a one-time $5 to $18.
Reviews punish the first group, and the search term "photo cleaner no subscription" has enough
demand that LuminaClean writes SEO posts against it.

The target sits in the indie group on price but gets two things wrong. Its free tier is a trial
that ends after a week of use, so the habit it is selling is the thing it takes away. And its
lifetime is $59.99, three times the yearly, when the category norm for a one-time unlock is $5 to
$30. The middle is open: a free daily ritual forever, a fair lifetime unlock, and no weekly plan
anywhere in the app.

## Competitor map

Four groups.

Publisher-scale cleaners. Swipewipe, Cleanup, CleanMy Phone, Slidebox. Big audiences, weekly
pricing, paid acquisition. Swipewipe's founder Adam O'Kane launched on Product Hunt in 2022, went
viral on TikTok with Gen Z, and sold to MWM in 2024. Their "On This Day" is one tab among many.

Indie daily-ritual cleaners. The target, This Day, Odays, Keep or Sweep, SwipeSwoop, PhotoSwipe,
Swoto, Swipe & Tidy, Sift, Sifty, Siftly. Most launched between mid-2025 and mid-2026. This Day
is the one with press and a clear free tier. The target is the one with the most honest privacy
stance and the most complete "do something with the memory" set (share, album, favorite).

Memory viewers with no cleanup. On This Day (Grossmann), Photos On This Day (Kyle Coburn), On
This Day Rewind, Years, Ayer, Memories: Relive Your Photos, Rewind: Memories on This Day, On This
Day: Memories (APPSKY Hong Kong, on-device vision), Timehop. They prove demand for the daily
memory and show what the widget should look like.

Native. Apple Photos has Memories, Featured Photos, and a Duplicates utility that merges copies
but not near-similar shots, and it has no "on this day" view and no swipe review. Google Photos has "Rediscover this day" and Memories. The
risk that Apple ships a native "On This Day" is the biggest external risk to the whole category.

## What we do better

Ranked by how much each bet moves retention or conversion. Each line says whether the target
already has it, so nobody mistakes table stakes for a moat.

Tier 1, the habit.

1. Never an empty day. Target: no, it has a manual date picker. If today's date has nothing,
   widen to this week in past years, then to a day you have not reviewed yet, then to a day the
   index knows has photos, even one you already reviewed. The app keeps an index of non-empty
   days, so the last fallback cannot come up empty. If the library itself is empty, show a
   completion state instead of a blank feed.
2. Moments, not a date. Target: no, it groups by year only. Group the day's photos by time gap
   and location, reverse-geocode the place name, and label the group "Lisbon, 2019, 14 photos".
   Same data, ten times the feeling.
3. Three piles plus a maybe. Target: keep and delete only, plus favorite. Add a maybe pile that
   comes back in 30 days. Maybe is where most guilt-deletes go, and it stops the "I deleted the
   wrong one" review.
4. Pending trash with unlimited undo. Target: yes, end-of-session deletion with undo. Match it,
   then commit in bounded, resumable batches of about 500 assets, so a 4,000-item session is
   eight prompts instead of thousands and no single PhotoKit transaction is large enough to hit
   the bulk-delete crashes reviewers report.
5. The widget does the work. Target: display-only widgets, paid. Ship an interactive Home Screen
   widget with keep and star buttons through App Intents, a Lock Screen widget, StandBy, and a
   Watch complication, in the free tier. Delete from the widget queues into pending trash,
   because the Photos confirmation dialog cannot show from a widget.
6. Free daily ritual, forever. Target: free for seven reviewed days, then paywalled. The daily
   review is the habit and the marketing. Never gate it.

Tier 2, the storage.

7. Cull the burst on the day. Target: no detection. Inside a moment, detect near-duplicates on
   device with Vision feature prints, show them side by side, pick the sharpest by default. This
   is where the bytes are.
8. Shrink instead of delete. Target: no. Strip Live Photo motion and compress videos from the
   same flow, with a byte count shown before you commit. This Day gates this behind Premium. We
   make it Pro too, but the counter is free so the value is visible.
9. Honest byte counts. Target: claims "real storage-saved stats". Sum real asset resource sizes,
   report iCloud-offloaded items separately, and label the total "pending" until the user empties
   Recently Deleted, because Photos keeps deleted items for up to 30 days and the app cannot
   purge that album. Show the steps to Recently Deleted with a button that opens Photos, since
   iOS has no link straight to that album, so the number in Settings catches up.

Tier 3, the memory.

10. Send this memory. Target: yes, share with date and location. Match it and add a story card
    and a one-tap send to the person in the photo via Messages.
11. Album from the day. Target: yes. Table stakes now. Match it.
12. Shared Library and shared albums included. Target: not mentioned. Mark shared items so the
    user knows a delete affects the family library. PhotoKit's cloud-shared source type marks
    shared albums, not Shared Library, so the badge depends on the spike finding a supported
    identifier.

Tier 4, trust.

13. Privacy as the headline. Target: yes, and stated well. Match it: no servers of ours and no
    analytics SDK. The only network traffic is Apple's own iCloud (for library sync and offloaded
    originals) and Apple's geocoder for place names, and geocoding is a setting the user can turn
    off. App Privacy label "Data Not Collected". Say it in the subtitle.
14. No weekly plan and no trial that charges silently. Target: no weekly plan either. A 7-day
    trial exists only on the annual plan and the app sends a local reminder 24 hours before it
    converts.
15. iPhone, iPad, and Mac from one SwiftUI codebase, with review state synced through CloudKit so
    you never re-review a photo. Target: iPhone only as far as the listing says.
16. Localized at launch: Japanese, German, Spanish, Portuguese (Brazil), French. Target: not
    stated. The category is global and most indies ship English only.
17. A name and subtitle that search can find. Target: name collides with PhotoSweeper and the
    subtitle has no keywords. See Names.

## Names

Constraints. Under ten letters. No collision with PhotoSweeper, Timehop, Swipewipe, This Day, or
the "Rewind" and "Years" families. Distinct in App Store search. A plausible `.app` domain. The
collision column reports what an App Store search surfaced. Domain and trademark checks were not
part of this research and are on the owner.

| Candidate | App Store collision found | Verdict |
|---|---|---|
| Winnow | None | First pick. Means separating the grain from the chaff. Short, premium, exact fit for keep-or-delete. Risk: some users will not know the word |
| Backswipe | None | Second pick. Names the gesture and the looking back. Playful, memorable, obviously an app |
| Rekindle | "Rekindle!" (relationship nudges) | Fits the Borrowed Fire brand family. Usable if the trademark check clears, but the existing app is close in spirit (daily nudge) |
| Daysweep | None, but DaySwipe exists | Descriptive. Sounds like DaySwipe when spoken. Medium risk |
| Yesteryear | "Dear Yesteryear" (shopping app) | Warm, nostalgic, long to type. Usable |
| Sameday | None in photos | Courier connotation. Pass |
| Hindsight | Five unrelated apps | Crowded. Pass |
| Lookback | Developer "Lookback App Co." holds it | Pass |
| Keepsake | Five apps, including "Keepsake - Photo Reviewer" | Pass |
| Memento, Rewind, Years, Ayer, Odays | Taken in this exact niche | Pass |
| Sift, Sifty, Siftly, Cull | Four swipe cleaners launched on these in 2026 | Pass |
| Retrospect, Ember, Kindling, Tinder | Trademarks in other categories | Pass |

App Store title is 30 characters and the subtitle is 30. The target spends its subtitle on "Tidy
the past to spark joy", which no one searches for. Working set for Winnow:

- Title: "Winnow: On This Day Cleaner" (27)
- Subtitle: "Relive today. Tidy your photos" (30)
- Keyword field (94 of 100 characters, and no words repeated from the title or subtitle because
  Apple indexes those separately):
  `swipe,delete,storage,duplicates,live,camera,roll,memories,declutter,space,clean,organize,burst`

## Pricing recommendation

| Tier | Price | What it unlocks |
|---|---|---|
| Free | $0 | Unlimited daily review of today's date, widgets, streak, pending trash, maybe pile, byte counter, star, share, album |
| Pro lifetime | $19.99, launch at $14.99 | Burst culling, Live Photo and video shrink, date-window and "any day" browsing, CloudKit sync, iPad and Mac, alternate icons |
| Pro yearly | $9.99 | Same as lifetime, for people who prefer it. Family Sharing on |

No weekly plan. No monthly plan. The free tier is the whole daily ritual, so the app is usable
forever without paying, and the paywall shows up when the user asks for a Pro feature, never on
first launch and never after day seven.

Against the target: our lifetime equals its yearly, our free tier never ends, and our widgets are
free. Against This Day: our lifetime is two thirds of its yearly.

Revenue reality. Swipewipe's estimated $1M a month comes from weekly pricing plus paid TikTok
acquisition. Fair pricing will not match that per user, so volume has to come from organic
channels and press. Sanity math before Apple's cut:

| Monthly downloads | Paid conversion | Blended price | Monthly revenue |
|---|---|---|---|
| 10,000 | 3% | $14.99 | $4,500 |
| 30,000 | 3% | $14.99 | $13,500 |
| 30,000 | 5% | $14.99 | $22,500 |

## Go-to-market

- TikTok built this category. Post the format that made Swipewipe: the day's memory, the swipe,
  the satisfying "empty trash", the storage before and after. Creator seeding, not paid ads, for
  the first quarter.
- Press that already covers this niche in 2026: 9to5Mac's Indie App Spotlight (This Day, May
  2026), MacStories (On This Day), iMore, and Cult of Mac. Lead the pitch with "no subscription
  required, and no servers of ours", because that is the angle the reviewers keep rewarding. The
  yearly plan exists, so never say "no subscription" flat.
- Product Hunt launch. SwipeSwoop got 150 upvotes there in September 2025 and Odays launched
  there too. The target never launched anywhere public.
- Reddit r/iphone and r/apple threads asking for a "swipe to delete" app appear weekly. Answer
  them with the app.
- Seasonal spikes: January cleanup, September new-iPhone migration, and the day the "iPhone
  Storage Almost Full" alert fires. Search ads on "photo cleaner" and "on this day" with a small
  budget once the free tier retention is proven.

## MVP scope

Six weeks to TestFlight, one developer.

Week 1 and 2. PhotoKit spike and the feed. Fetch by creation date across years, fall back to the
week, then to unreviewed days. Moments grouping by time gap and location. Review state store
keyed by the asset's local identifier for the on-device cache and by its iCloud identifier
(PhotoKit's cloud identifier mapping) for the synced record, because the local identifier differs
per device and would make synced photos come back for review.

Week 3. Swipe deck, three piles plus maybe, pending trash, bounded batched delete at commit, byte
counter from asset resources, share sheet with date and place, album from the day.

Week 4. Widgets. Home Screen with interactive keep and star, Lock Screen, StandBy. Daily local
notification. Streak.

Week 5. StoreKit 2 with lifetime and yearly products, paywall, restore. Privacy label work. App
Store assets.

Week 6. Polish, large-library performance pass (100K assets), localization pass, TestFlight.

Pro features (burst culling, Live Photo and video shrink, CloudKit sync, iPad and Mac) ship in
the two releases after 1.0.

Technical notes.

- Photos always shows its own confirmation dialog on delete, with the item count. Batched
  deletes at commit are the only way to make that tolerable.
- There is no public API to restore from "Recently Deleted". The pending trash is ours, so undo is
  free until commit.
- PhotoKit's cloud-shared source type identifies shared albums, not iCloud Shared Photo Library
  membership, and no supported identifier for the latter is confirmed. The spike decides whether
  Shared Library badges ship in 1.0.
- Near-duplicate detection: Vision feature prints and a distance threshold, all on device.
  Sharpness: Laplacian variance on the thumbnail.
- Live Photo to still: create a new still asset from the photo resource, then queue the original
  into pending trash. Video shrink: export at a lower bitrate with AVFoundation, then queue the
  original. In both cases copy the creation date, location, and favorite flag onto the new
  asset, re-add it to every album the original was in, and render from the edited version so
  adjustments survive. Without that step the replacement silently drops the user's organization.
- Interactive widgets run through App Intents. Keep and star are safe from the widget. Delete
  queues only.
- iCloud-optimized libraries stall on full-resolution loads. Review on thumbnails, load full
  resolution only for the cull view and for Shrink, which downloads an offloaded original with
  visible progress and a cancel, and never block a swipe on a network fetch.

## Risks

- Apple ships a native "On This Day" in Photos. Google has had one since 2015. The cleanup half
  survives that, the memory half does not. Ship the cleanup half well.
- The target's developer ships with AI tooling, has a newsletter audience, and added "Group by
  Year" eleven months in. Expect him to close obvious gaps if he sees them. The moat is the
  habit design, the pricing stance, and distribution, not the feature list.
- Photos permission drop-off. Ask for full library access only after showing what the app does
  with a limited selection.
- The template is cheap to copy. Fifteen apps prove it.
- Fair pricing means slower revenue. Decide up front whether this is a side product or a
  business that needs paid acquisition.

## Sources

- Target listing, verified on device 2026-09-08: https://apps.apple.com/app/id6752840632
- Target site: https://omarknows.app/on-this-day/
- Target privacy policy: https://omar.shahine.com/apps/on-this-day-privacy
- Developer's account of his first year of apps: https://www.omarknows.com/p/four-ios-apps-one-year-and-a-lot
- Developer's app portfolio: https://omarknows.app/
- App id resolution: https://apps.apple.com/jp/app/on-this-day-photo-sweeper/id6752840632?see-all=customers-also-bought-apps&platform=iphone
- This Day, 9to5Mac Indie App Spotlight: https://9to5mac.com/2026/05/02/indie-app-spotlight-this-day-photo-cleanup-tool/
- This Day listing: https://apps.apple.com/us/app/this-day-photo-cleaner/id6758584686
- On This Day (Grossmann), MacStories: https://www.macstories.net/reviews/on-this-day-my-new-favorite-way-to-revisit-old-photos/
- Swipewipe review and pricing (Favvy): https://www.favvyapp.com/en/blog/swipewipe-review
- Swipewipe review and pricing (InsanelyMac): https://www.insanelymac.com/blog/swipewipe-photo-cleaner-review/
- Swipewipe acquisition (TechCrunch): https://techcrunch.com/2024/06/25/gen-z-photos-app-swipewipe-sells-to-french-publisher-mwm-in-its-largest-acquisition-to-date
- Swipewipe founder interview: https://aryamansharda.medium.com/indiewatch-20-swipewipe-by-adam-okane-3557a37cbd7d
- Swipewipe estimates: https://app.sensortower.com/overview/1583884012?country=US
- Category ranking: https://www.swipephotos.com/compare/best-swipe-photo-apps
- Category ranking: https://www.favvyapp.com/en/blog/top-5-apps-to-clean-photos
- No-subscription cleaners: https://luminaclean.app/blog/best-photo-cleaner-no-subscription-iphone.html
- Cleanup pricing and reviews: https://tools.macgasm.net/reviews/cleanup-app-review/
- Slidebox pricing: https://sourceforge.net/software/product/Slidebox/
- Favvy pricing: https://www.favvyapp.com/en/pricing
- Odays: https://www.producthunt.com/products/odays
- SwipeSwoop launch: https://www.producthunt.com/products/swipeswoop
- Photos On This Day: https://apps.apple.com/us/app/photos-on-this-day/id1620659723
- On This Day: Memories (APPSKY): https://apps.apple.com/jp/app/on-this-day-memories/id6758696641
- Google Photos Rediscover this day: https://techcrunch.com/2015/08/20/google-photos-introduces-rediscover-this-day-to-help-you-reminisce/
- Apple Photos duplicates: https://support.apple.com/guide/iphone/merge-duplicate-photos-and-videos-iph1978d9c23/ios
- PhotoSweeper (name collision): https://apps.apple.com/us/app/photosweeper/id463362050?mt=12
