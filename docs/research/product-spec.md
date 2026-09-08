# Product spec: Winnow (working name)

A daily photo ritual that leaves your library smaller and better. Open it with your coffee, see
today's date across every year you have, keep the good ones, let the rest go, and get your
storage back without a subscription.

Companion to [similar-apps.md](similar-apps.md) (the evidence) and
[on-this-day-photo-sweeper.md](on-this-day-photo-sweeper.md) (the target teardown). Status:
proposal, 2026-09-08. Nothing here is built.

## The premise we must match

The category has settled on a loop, and thirty-three apps prove users accept it. Day one has to
have all of it or we lose the comparison before our differences matter.

1. Today's date across every past year, photos and videos, Live Photos playing.
2. Swipe right to keep, left to delete. Tap to undo the last one.
3. Nothing is deleted until the session ends, and the end-of-session screen shows what will go.
4. Real storage numbers, a streak, and an optional daily reminder.
5. Share a memory with its date and place. Star it. Make an album from the day.
6. A date picker for any day.
7. On device only. No account, no ads, no analytics.
8. Home Screen widget showing the day's memory.

The target app already ships every item on this list. So do This Day and, in pieces, Swipewipe.
This is the entry fee, not the product.

## Who it is for and when they arrive

- The storage-full person. The iPhone alert fired, iCloud is nagging, and they want to delete a
  lot fast without deleting the wrong thing. They search "photo cleaner". Storage first,
  memories are the reward.
- The morning-ritual person. They used Timehop or Facebook's On This Day and miss it. They
  search "on this day" or "photos from this day last year". Memories first, cleanup is the
  bonus.
- The switcher. They pay Swipewipe weekly and resent it, or they hit the target's seven-day wall.
  They search "swipewipe alternative" and "photo cleaner no subscription".

The product serves all three with one loop and different first screens (see Onboarding).

## Principles

- The ritual is free forever. The paywall never interrupts a daily review.
- Nothing leaves the device except through Apple's own iCloud. No servers of ours.
- Every delete is reversible until the user says otherwise, and the app never shows a storage
  number it cannot stand behind.
- The feed is never empty.
- No weekly plan. No trial that charges without warning.
- One name for each thing, in the app and in this document. "Trash" is the pending pile.
  "Commit" is the moment Photos deletes. "Moment" is a group of photos from one place and time.

## Gap fillers

Things users ask for that few or no apps ship. Each has a demand source in similar-apps.md.

1. Near-duplicate culling inside the day. Detection tools scan the whole library and produce
   lists no one can review ("20,000 similar images"). Ritual apps have no detection at all. We
   detect only within today's moments, on device, and show a burst as one card: the sharpest
   shot proposed, the rest behind it. Demand: the top unmet need in reviews.
2. Scope the day to a source or album. "Only the Family album", "only my library, not Shared",
   "skip screenshots". Two viewers do it, no cleaner does. Demand: Rewind reviewers, Memories:
   Relive Your Photos changelog.
3. Shared Photo Library made safe. Shared items carry a badge, and the commit screen separates
   "yours" from "shared with family" with its own confirmation. Demand: Apple's own warning and
   Photos On This Day's positioning.
4. Shrink instead of delete. Live Photo to still and video re-encode from the same card, with
   the byte delta shown before commit, metadata and album membership copied to the replacement.
   Demand: "no easy way to batch convert Live Photos"; CleanMy Phone's main paid draw.
5. Screenshots as their own lane. A screenshot never appears in the memory feed. They get a
   separate weekly sweep, grouped by source app where iOS exposes it. Demand: a whole sub-genre
   of screenshot-only apps exists.
6. Reversible by design. Trash, batch commit, and a restore path. Demand: undo and
   review-before-delete are advertised as differentiators; data-loss reviews are the worst
   one-stars in the category.
7. Stop Live Photos auto-playing. A setting, and a long-press to play. Demand: Memories: Relive
   Your Photos reviews.
8. iPad and Mac with synced review state. Swipe & Tidy has the platforms, Sift has the sync,
   nobody has both. Demand: PhotoSweeper Mobile and SwipePhotos exist because of it.

## Enhancements that make people switch

The gap fillers close complaints. These create the reason to tell someone else.

1. Never an empty day. The ladder: today's date across years; then this week across years;
   then a day with photos you have not reviewed; then a day the index knows has photos, even one
   you already reviewed, framed as "a year ago this month"; then, if the library is empty, a
   completion state. Timehop is the only app with any fallback, and it falls back to trivia.
2. Moments, not a date. The day's photos grouped by time gap and location, with a place name
   and a count: "Lisbon, 2019, 14 photos". The finest grain anywhere else is "by year". This is
   the same data and ten times the feeling, and it is the unit the cull works on.
3. Keep, delete, star, maybe. The maybe pile returns in 30 days. It absorbs the guilt-deletes
   that produce "I deleted the wrong one" reviews and it is a second daily touch.
4. The widget does the work. Interactive Home Screen widget with keep and star buttons (App
   Intents), a Lock Screen widget, StandBy, and a Watch complication that shows the memory and
   takes a keep or star. No app in the category has any of these. Widgets are free.
5. Honest bytes. The counter says "pending" until Recently Deleted is emptied, and offers the
   one-tap path there. Every competitor claims "storage saved" the moment you swipe, and Settings
   disagrees with them for 30 days.
6. Send it to the person in it. From the moment view, one tap opens Messages to a recent
   contact with the photo and the "N years ago today" caption. Then & Now pairs (old photo next
   to today's) as a share card, the format Timehop and Ayer proved.
7. Lifetime for the price of a year. $19.99 once. The target charges $59.99, Swipewipe charges
   that per year in some regions, and This Day is $29.99 a year.

## Screens

Today. The first screen every day. A header with the date and the year range found. Moments as
cards, each with a place name, count, and a burst indicator. A streak chip and a pending-trash
chip. If the ladder had to fall back, the header says which rung ("This week, 2021").

Review. The swipe deck for one moment. A card is one photo, or one burst with the proposed
keeper on top and a "see all N" flip. Right keeps, left trashes, up stars, down sends to maybe.
Tap undoes. Long-press plays a Live Photo or video. The bottom bar shows bytes pending for this
moment.

Cull. The side-by-side view for a burst. Thumbnails in a row, the sharpest proposed, tap to
swap the keeper, swipe down to trash the rest. Full resolution loads only here.

Trash. Everything pending, grouped by moment, with shared-library items in their own section.
Restore any item. "Commit" runs bounded batches of about 500 with one system prompt each, and a
progress bar so a 4,000-item day is eight prompts and never a crash. After commit, a card
explains Recently Deleted and offers the shortcut.

Maybe. The 30-day pile, sorted by return date. Items come back into Today on their day.

Screenshots. A separate lane, opened weekly by a badge. Grid, select all by source app, trash.

Settings. Sources (library, Shared Library, specific albums), Live Photo autoplay, reminder
time, geocoding on or off, Pro, restore purchases, privacy page.

Widgets. Small: one photo and the years-ago label. Medium: photo plus keep and star buttons.
Large: the day's moments. Lock Screen: photo count and a tap into Today. Watch: photo and a
keep or star.

## Onboarding

Three screens at most. What the app does, in one sentence. The privacy statement, in one
sentence. The Photos permission, asked with limited access first and full access explained
after the first review. No paywall, no account, no email. The storage-full person sees a bytes
estimate on screen one; the ritual person sees today's memory. Both get to Today in under 20
seconds.

## Free and Pro

| Tier | Price | What it includes |
|---|---|---|
| Free | $0 | Today, Review, Trash, Maybe, all widgets, streak, reminders, share, star, album, sources and scopes, screenshots lane |
| Pro lifetime | $19.99, launch at $14.99 | Cull with detection, Shrink, any-day and date-window browsing, CloudKit sync, iPad and Mac, alternate icons |
| Pro yearly | $9.99 | Same, for people who prefer it. Family Sharing on |

The paywall appears only when the user taps a Pro feature. It shows both prices with lifetime
first. The yearly plan has a 7-day trial and the app sends a local notification 24 hours before
it converts.

## Deletion safety

- Photos shows its own confirmation with a count on every delete call. We batch, we never
  suppress.
- There is no API to restore from Recently Deleted. Our trash is the undo; after commit we point
  to the album.
- Shared Library items are marked from the asset source and confirmed separately.
- Shrink copies creation date, location, and favorite onto the replacement, re-adds it to every
  album the original was in, renders from the edited version, and trashes the original only
  after the replacement exists.
- A session that crashes mid-commit resumes from the last completed batch.

## Empty-day ladder, precisely

The app maintains an index of days that have at least one non-screenshot asset, refreshed on
launch and on Photos change notifications. The ladder queries the index, so the last rung cannot
return nothing. Each rung is labeled in the Today header so the user knows why they are seeing
it. Rungs 2 and 3 are free; rung 4 draws from the whole library and is the same engine as
any-day browsing.

## Release plan

1.0, six weeks to TestFlight. The premise list, Today with moments, Review, Trash with batching,
Maybe, the empty-day ladder, sources and scopes, Shared Library badges, screenshots lane,
interactive and Lock Screen widgets, StoreKit 2 with both Pro products, five languages.

1.1. Cull with on-device detection and the burst card. Shrink for Live Photos.

1.2. Video shrink. CloudKit sync. iPad. Watch complication and StandBy.

1.3. Mac. Then & Now share cards. Send to the person in it.

## Metrics

| Metric | Target at 90 days |
|---|---|
| Day 7 retention | 35% |
| Days reviewed per active user per week | 4 |
| Trash committed per active user per week | 1 |
| Free to Pro conversion, lifetime plus yearly | 3% |
| One-star reviews mentioning data loss | 0 |
| Median Today load on a 100K library | under 1 second |

## Non-goals

No contacts, calendar, or "whole phone" cleanup. No AI enhancement or restoration. No social
feed and no external photo sources. No ads, ever. No weekly plan, ever. No cloud of ours.

## Risks

- iOS 27 reportedly upgrades Photos Memories. If Apple ships a true same-date view with a
  widget, the viewer half of the category is gone. The cleanup half, the moments, the cull, and
  the trash survive. Build those first.
- Photos permission drop-off. Limited access first, and a working Today with whatever was
  granted.
- Detection quality. Ship the cull as a proposal the user confirms, never an automatic delete.
- Performance on optimized-storage libraries. Thumbnails only in Review; full resolution only in
  Cull; no swipe ever waits on a network fetch.
- Name collisions. "On This Day" is taken many times over; the Grossmann app had to ship as
  "On This Day Rewind". Pick from the shortlist in the teardown and check the trademark before
  the first TestFlight build.
