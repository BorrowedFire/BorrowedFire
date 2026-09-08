# On This Day • Photo Sweeper: teardown and build plan

Target: App Store id 6752840632, "On This Day • Photo Sweeper".
Research date: 2026-09-08.

## Verdict

The app is a small, near-invisible entry in a crowded template: show the user photos taken on
today's date in past years, let them swipe to keep or delete, count the storage saved, and sell a
subscription. At least fifteen apps ship that exact loop. Two of them matter. Swipewipe owns the
category by volume and charges the most. This Day (Raymond Kim) owns the "one day at a time"
framing with the indie press and charges a fair price.

The opening is real but it is not "the same app with a nicer icon". The category has three
structural weaknesses nobody has fixed: empty days, weekly billing that users hate, and a memory
feed with no context and no way out except delete. Our version wins on those three, prices with a
lifetime tier, and treats privacy and the widget as the product instead of features.

## What we could verify, and what we could not

Verified sources: search-engine index snippets of App Store listings, review pages, and press
coverage. Not verified: the target's own listing page, its reviews page, and any app-intelligence
estimate for it (Sensor Tower, Appfigures, Apptopia, AppAgg). None of those were reachable during
research, so everything below about the target comes from index snippets, and everything about
competitors comes from snippets of their listings, reviews, and press.

Facts we could pin down about the target:

- The id resolves to "On This Day • Photo Sweeper" on the App Store.
- The only page any search engine has indexed is the Japanese storefront's "customers also
  bought" page. No US listing page, no reviews page, no press, no Reddit, no TikTok, no Product
  Hunt, no developer site surfaced under any query.
- Neighboring ids hint at age. SwipeSwoop (6752326592) shipped version 1.0.0 on 2025-09-20 and
  This Day (6758584686) shipped in early 2026, so the target's record was probably created in the
  second half of 2025. Apple assigns the id when the record is created, which can be well before
  release, so treat this as a hint. The version history in the manual check is the evidence.
- The name collides with PhotoSweeper, a Mac duplicate finder sold since 2011 by Overmacs, and
  with PhotoSweeper Mobile (2024). Every search for the target's name returned those apps first.
  That is an ASO problem the developer chose for themselves.

Facts we could not pin down: developer name, subtitle, description text, price points, rating
count, version history, privacy labels, screenshots. The next section reconstructs the feature
set from the category, and marks it as reconstruction.

Five-minute manual check for whoever has an iPhone in hand. Open the link, then record:

1. Developer name and whether it links to a developer page with other apps.
2. Subtitle and the first two lines of the description.
3. In-app purchase list with prices (scroll to Information).
4. Rating count and average, and the date of the oldest review.
5. Version history dates. Note the time since the last update and whether the developer has
   other apps. One entry on an app that is months old suggests low activity, not proof of
   abandonment.
6. App Privacy label. "Data Not Collected" or something else.
7. Screenshot of the paywall after install. Note trial length and default plan.

Paste those into the "Target listing" section at the end of this file.

## What the app does (reconstructed)

Treat this as the category template, not a verified feature list. Every "On This Day" cleaner we
could read does all of it, and the target's name promises the first two.

- Daily feed of photos and videos taken on today's date in each prior year.
- Swipe right to keep, swipe left to delete. Deleted items go to a trash list, then the app calls
  the Photos delete, which triggers the iOS confirmation dialog.
- Storage-saved counter and a running count of photos reviewed.
- Streak and a daily reminder notification.
- Home Screen widget showing today's memory.
- Some add month-by-month browsing, a duplicates finder, or screenshot cleanup.
- Freemium. Free tier gated by a daily swipe cap or ads. Paywall with weekly and yearly plans and
  a three-day trial.

## What the app does not do (and neither does the category)

These gaps come from reading reviews and comparison articles across Swipewipe, Cleanup,
Slidebox, This Day, Favvy, Clever Cleaner, LuminaClean, Odays, and the memory-viewer apps.

1. Empty days. If you took no photos on this date in any prior year, the app has nothing to
   show. A daily-habit product with a random empty day is a retention leak. No app we found has a
   fallback.
2. Weekly billing. The loudest complaint in every review set. Swipewipe's paywall shows $8.99 to
   $9.99 a week, and Cleanup shows $4.99 to $11.99 a week depending on the source. Users describe
   the trial-to-charge flow as a trap.
3. Privacy fear. Swipewipe's privacy policy says photos may be uploaded. Reviewers flag it. The
   free apps (Clever Cleaner, LuminaClean, Cull) all lead with "100% on device" because it sells.
4. No context. The feed is a date. No place name, no grouping into moments, no "this was the
   trip to Lisbon". The nostalgia half of the product is thin.
5. Delete is the only exit. Keep or delete. Nothing to do with a good memory except leave it.
   Timehop proved that sharing a memory is the retention loop, and none of the cleaners have it.
6. No burst culling on the day. The storage is in the eleven near-identical shots of the same
   sunset, not in the one screenshot. Only the general cleaners do similar-photo detection, and
   reviewers call Swipewipe's unreliable.
7. Crashes on bulk delete. Multiple Swipewipe reviews report crashes when deleting around 4,000
   items at once.
8. No Live Photo or video compression in the daily flow. This Day is the exception and gates it
   behind Premium.
9. No iCloud Shared Photo Library or shared albums. Photos On This Day (a viewer, not a
   cleaner) is the only app that mentions shared photos.
10. No iPad or Mac parity, no sync of what you already reviewed. SwipePhotos is the one
    cross-device pick and it is a general cleaner.
11. No undo after commit. Everything relies on the Photos "Recently Deleted" album.
12. No interactive widget, no Lock Screen widget, no Watch, no Shortcuts.

## The goal

Two jobs fused into one habit.

- The nostalgia hit. Facebook's On This Day, Timehop, and Google Photos' "Rediscover this day"
  (2015) trained a decade of users to expect a daily memory. Apple Photos has Memories and a
  Featured Photos widget but no explicit "on this day" surface, so the gap is real on iPhone.
- The storage chore. "iPhone storage full" is evergreen search demand. Cleaners monetize the
  anxiety.

The fusion is the insight. Nostalgia makes the chore pleasant, which makes it daily, which makes
a subscription defensible. The target app is a bet that a focused, daily version of Swipewipe's
"On This Day" tab can stand alone. This Day made the same bet six months later with better
execution and got the 9to5Mac Indie App Spotlight for it.

## Pricing landscape

| App | Free tier | Paid | Notes |
|---|---|---|---|
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
buy the users back with TikTok ads. The indies charge $5 to $30 a year or a one-time $5 to $18.
Reviews punish the first group and the search term "photo cleaner no subscription" has enough
demand that LuminaClean writes SEO posts against it. The middle is open: a free daily ritual with
a fair lifetime unlock and no weekly plan anywhere in the app.

## Competitor map

Four groups.

Publisher-scale cleaners. Swipewipe, Cleanup, CleanMy Phone, Slidebox. Big audiences, weekly
pricing, paid acquisition. Swipewipe's founder Adam O'Kane launched on Product Hunt in 2022, went
viral on TikTok with Gen Z, and sold to MWM in 2024. Their "On This Day" is one tab among many.

Indie daily-ritual cleaners. This Day, Odays, the target, Keep or Sweep, SwipeSwoop, PhotoSwipe,
Swoto, Swipe & Tidy, Sift, Sifty, Siftly. Most launched between mid-2025 and mid-2026. This Day
is the one with press and a clear free tier.

Memory viewers with no cleanup. On This Day (Grossmann), Photos On This Day (Kyle Coburn), On
This Day Rewind, Years, Ayer, Memories: Relive Your Photos, Rewind: Memories on This Day, On This
Day: Memories (APPSKY Hong Kong, on-device vision), Timehop. They prove demand for the daily
memory and show what the widget should look like.

Native. Apple Photos has Memories, Featured Photos, and an exact-duplicates utility, but no "on
this day" view and no swipe review. Google Photos has "Rediscover this day" and Memories. The
risk that Apple ships a native "On This Day" is the biggest external risk to the whole category.

## What we do better

Ranked by how much each bet moves retention or conversion, with the cheapest bets first inside
each tier.

Tier 1, the habit.

1. Never an empty day. If today's date has nothing, widen to this week in past years, then to
   a day you have not reviewed yet, then to a day the index knows has photos, even one you
   already reviewed. The app keeps an index of non-empty days, so the last fallback cannot come
   up empty. If the library itself is empty, show a completion state instead of a blank feed.
2. Moments, not a date. Group the day's photos by time gap and location, reverse-geocode the
   place name, and label the group "Lisbon, 2019, 14 photos". Same data, ten times the feeling.
3. Three piles plus a maybe. Keep, delete, star (writes the Photos favorite), and a maybe pile
   that comes back in 30 days. Maybe is where most guilt-deletes go, and it stops the "I deleted
   the wrong one" review.
4. Pending trash with unlimited undo. Nothing leaves the library until the user taps "empty
   trash". Commit in bounded, resumable batches of about 500 assets, so a 4,000-item session is
   eight prompts instead of thousands and no single PhotoKit transaction is large enough to hit
   the bulk-delete crashes reviewers report.
5. The widget does the work. Interactive Home Screen widget with keep and star buttons through
   App Intents, a Lock Screen widget, StandBy, and a Watch complication. Delete from the widget
   queues into pending trash, because the Photos confirmation dialog cannot show from a widget.

Tier 2, the storage.

6. Cull the burst on the day. Inside a moment, detect near-duplicates on device with Vision
   feature prints, show them side by side, pick the sharpest by default. This is where the bytes
   are.
7. Shrink instead of delete. Strip Live Photo motion and compress videos from the same flow, with
   a byte count shown before you commit. This Day gates this behind Premium. We make it Pro too,
   but the counter is free so the value is visible.
8. Honest byte counts. Sum real asset resource sizes, not estimates, and report iCloud-offloaded
   items separately. Label the total "pending" until the user empties Recently Deleted, because
   Photos keeps deleted items for up to 30 days and the app cannot purge that album. Show the
   one-tap path to Recently Deleted so the number in Settings catches up.

Tier 3, the memory.

9. Send this memory. One tap to share the day's best photo to the person in it via Messages, or
   save a story card. Nostalgia has a social loop. Cleaners ignore it.
10. Shared Library and shared albums included, marked so the user knows a delete affects the
    family library.

Tier 4, trust.

11. Privacy as the headline. No servers of ours and no analytics SDK. The only network traffic
    is Apple's own iCloud (for library sync and offloaded originals) and Apple's geocoder for
    place names, and geocoding is a setting the user can turn off. App Privacy label "Data Not
    Collected". Say it in the subtitle. The free competitors already proved this converts.
12. No weekly plan. No trial that charges silently. A 7-day trial exists only on the annual plan
    and the app sends a local reminder 24 hours before it converts.
13. iPhone, iPad, and Mac from one SwiftUI codebase, with review state synced through CloudKit so
    you never re-review a photo.
14. Localized at launch: Japanese, German, Spanish, Portuguese (Brazil), French. The target lives
    on the Japanese store. The category is global and most indies ship English only.

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

App Store title is 30 characters and the subtitle is 30. Working set for Winnow:

- Title: "Winnow: On This Day Cleaner" (27)
- Subtitle: "Relive today. Tidy your photos" (30)
- Keyword field (94 of 100 characters, and no words repeated from the title or subtitle because
  Apple indexes those separately):
  `swipe,delete,storage,duplicates,live,camera,roll,memories,declutter,space,clean,organize,burst`

## Pricing recommendation

| Tier | Price | What it unlocks |
|---|---|---|
| Free | $0 | Unlimited daily review of today's date, widget, streak, pending trash, byte counter, star |
| Pro lifetime | $19.99, launch at $14.99 | Burst culling, Live Photo and video shrink, maybe pile, date-window and "any day" browsing, CloudKit sync, iPad and Mac, alternate icons |
| Pro yearly | $9.99 | Same as lifetime, for people who prefer it. Family Sharing on |

No weekly plan. No monthly plan. The free tier is the whole daily ritual, so the app is usable
forever without paying, and the paywall shows up when the user asks for a Pro feature, never on
first launch.

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
  there too.
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

Week 3. Swipe deck, three piles plus maybe, pending trash, one batched delete at commit, byte
counter from asset resources.

Week 4. Widgets. Home Screen with interactive keep and star, Lock Screen, StandBy. Daily local
notification. Streak.

Week 5. StoreKit 2 with lifetime and yearly products, paywall, restore. Privacy label work. App
Store assets.

Week 6. Polish, large-library performance pass (100K assets), localization pass, TestFlight.

Pro features (burst culling, Live Photo and video shrink, CloudKit sync, iPad and Mac) ship in
the two releases after 1.0.

Technical notes.

- Photos always shows its own confirmation dialog on delete, with the item count. One batched
  delete per session is the only way to make that tolerable.
- There is no public API to restore from "Recently Deleted". The pending trash is ours, so undo is
  free until commit.
- PhotoKit exposes both the personal library and the shared iCloud library through fetch
  options. Confirm the exact source-type flags in the spike before promising shared support.
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
  resolution only for the side-by-side cull view, and never block a swipe on a network fetch.

## Risks

- Apple ships a native "On This Day" in Photos. Google has had one since 2015. The cleanup half
  survives that, the memory half does not. Ship the cleanup half well.
- Photos permission drop-off. Ask for full library access only after showing what the app does
  with a limited selection.
- The template is cheap to copy. Fifteen apps prove it. The moat is the habit design and the
  pricing stance, not the code.
- Fair pricing means slower revenue. Decide up front whether this is a side product or a
  business that needs paid acquisition.

## Sources

- App id resolution: https://apps.apple.com/jp/app/on-this-day-photo-sweeper/id6752840632?see-all=customers-also-bought-apps&platform=iphone
- SwipeSwoop launch date (id calibration): https://huntscreens.com/en/products/swipeswoop and https://www.producthunt.com/products/swipeswoop
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
- Photos On This Day: https://apps.apple.com/us/app/photos-on-this-day/id1620659723
- On This Day: Memories (APPSKY): https://apps.apple.com/jp/app/on-this-day-memories/id6758696641
- Google Photos Rediscover this day: https://techcrunch.com/2015/08/20/google-photos-introduces-rediscover-this-day-to-help-you-reminisce/
- Apple Photos duplicates: https://support.apple.com/guide/iphone/merge-duplicate-photos-and-videos-iph1978d9c23/ios
- PhotoSweeper (name collision): https://apps.apple.com/us/app/photosweeper/id463362050?mt=12

## Target listing (fill in by hand)

| Field | Value |
|---|---|
| Developer | |
| Subtitle | |
| In-app purchases | |
| Rating count and average | |
| Version history | |
| Privacy label | |
| Paywall (trial, default plan) | |
