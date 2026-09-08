# Similar apps: feature matrix and unmet needs

Companion to [on-this-day-photo-sweeper.md](on-this-day-photo-sweeper.md) (the target teardown)
and [product-spec.md](product-spec.md) (what we build). Research date: 2026-09-08. Sources are
search-index snippets of App Store listings, reviews, developer sites, and press. Fields that no
source stated are marked "n/f" (not found) rather than guessed. Prices are US unless noted and
several publishers A/B test them by region.

## The three groups

Daily-ritual cleaners show today's date across past years and let you swipe. Publisher-scale
cleaners are storage tools first, with a memory tab at most. Memory viewers show the day and
mostly do not delete. Our product sits in the first group and borrows the best of the other two.

## Feature matrix

Columns: App carries the App Store id where one was found (SwipePhotos sells from its own site).
OTD = "On This Day" feed. Sim = similar or near-duplicate detection (not just exact). Shrink =
Live Photo to still or video compression. Trash = pending deletion with undo before commit. Wid =
Home Screen widget. Multi = iPad, Mac, or sync beyond iPhone. Free = what the free tier gives.
Paid = cheapest recurring and one-time prices seen.

| App | Group | OTD | Sim | Shrink | Trash | Wid | Multi | Free | Paid | Ratings |
|---|---|---|---|---|---|---|---|---|---|---|
| On This Day • Photo Sweeper (target), id6752840632 | ritual | yes, by year | no | no | yes | yes, paid | n/f | 7 reviewed days | $1.99 mo, $19.99 yr, $59.99 life | 4, 5.0 |
| This Day (Raymond Kim), id6758584686 | ritual | yes | exact only | Live to still | n/f | n/f | iPad | daily review | $3.99 mo, $29.99 yr | n/f |
| Odays, id6749476828 | ritual | yes, small batch | no | no | n/f | n/f | no | daily review | mo, yr, lifetime (n/f) | n/f |
| Keep or Sweep, id6740060949 | ritual | yes | no | no | undo | n/f | n/f | n/f | n/f | n/f |
| SwipeSwoop, id6752326592 | ritual | not confirmed | no | no | n/f | n/f | n/f | n/f | subscription | too few |
| PhotoSwipe (Rica Harz), id6748684876 | ritual | yes | no | no | end-of-month review | n/f | n/f | n/f | $3.99 wk, $19.99 yr | too few |
| Swoto, id6754226061 | ritual | yes, plus random and year modes | yes, plus faces | no | n/f | n/f | n/f | n/f | subscription | too few |
| Swipe & Tidy, id6761130588 | ritual | no | AI blur and dup | no | mandatory review screen | n/f | Mac, visionOS | 50 swipes a day | $2.99 wk, $19.99 yr, $29.99 life | n/f |
| Swipy, id1617533426 | ritual | yes | yes | no | undo | n/f | n/f | n/f | $3.99 mo, $19.99 yr, $29.99 life, no weekly | 104, 4.5 |
| LuminaClean, id6757949814 | ritual and tools | yes ("Daily Bites") | yes, plus blur | both | n/f | n/f | no | 65 deletes, then 10 a day | $4.99 mo, $17.99 life | 11, 4.8 |
| Daily Delete (In Ordinem), id1551399205 | ritual | implied | yes | no | n/f | n/f | n/f | free with ads | subscription | ~1,700, 4.7 |
| Photos Cleaner: Swipe & Delete (TP), id6742649462 | ritual | yes | no | no | undo | yes | iPad | n/f | IAP | n/f |
| Swipe Clean (ARK), id6475195875 | ritual | yes | yes | no | Quick Clean commit | n/f | iPad | 3-day trial | $4.99 wk, $19.99 yr | n/f |
| Swipewipe (MWM), id1583884012 | publisher | yes, pinned | yes, plus blur and screenshots | no | bookmarks | yes, iOS 18 | Android | session cap, ~7 h cooldown, ads | $4.99 to $9.99 wk, $19.99 to $109.99 yr by region | 84K, 4.7 |
| Slidebox (MWM), id984305203 | publisher | no | manual compare | no | confirm step | n/f | iPad, Android, visionOS | basic | $4.99 mo, $49.99 yr, $19.99 one-time | 16K, 4.8 |
| Cleanup (BPMobile), id1510944943 | publisher | no | yes, plus best photo | video | n/f | n/f | Android, visionOS | ads, trial | $7.99 wk, $44.99 life | 574K, 4.7 |
| CleanMy Phone (MacPaw), id1277110040 | publisher | no | yes, AI categories | both | n/f | n/f | iPad | 3-day trial | ~$24.99 yr | 21.8K, 4.6 |
| Clever Cleaner, id1666645584 | free tool | no | yes | Live to still | n/f | n/f | iPad, visionOS | everything (2026 daily caps disputed) | none | 81K, 4.78 |
| Favvy, id6743979781 | free-first | no | yes, bursts | no | n/f | n/f | Android | 100 swipes a day, earnable | Pro (n/f) | iOS 4.7, Android 3.47 |
| SwipePhotos, swipephotos.com | paid tool | no | yes | no | n/f | n/f | iPhone, iPad, Mac, one purchase | none | $34.99 yr, lifetime (n/f) | n/f |
| Cull, id6761037751 | one-time tool | no | burst grading | no | n/f | n/f | n/f | IAP | one-time (n/f) | too few |
| Sift: Organize, id6762099897 | tool | no | no | no | shake to undo | n/f | iCloud sync | n/f | n/f | n/f |
| Sifty, id6754003221 | tool | no | no | no | n/f | n/f | n/f | 40 photos a day | $3.99 wk, $29.99 yr | n/f |
| Timehop, id569077959 | viewer | yes, plus social sources | no | no | no delete | yes | Android | free with ads | Timehop+ (n/f), 7-day trial | ~172K, 4.8 |
| On This Day Rewind (Grossmann), id6754617354 | viewer | yes, by year | no | no | delete only | 4 sizes, adjustable count | iPad, Vision Pro | last 3 years | $4.99 one-time or $0.99 mo | too few |
| Photos On This Day (Coburn), id1620659723 | viewer | yes, plus Shared Photos | no | no | no | yes | iPad, Vision Pro | free | n/f | n/f |
| Memories: Relive Your Photos, id1037130497 | viewer | yes, source selectable | no | no | delete only | yes | no | everything | none | n/f |
| On This Day Photos, id6467105878 | viewer | yes, any day | no | no | no | yes, tap to cycle | iPhone, iPad, Mac | n/f | n/f | n/f |
| ThenNow, id6711347898 | viewer | yes, plus Footprints map | no | no | no | n/f | n/f | free | IAP | n/f |
| On This Day: Memories (APPSKY), id6758696641 | viewer | yes, vision-curated | no | no | curate | n/f | Mac, visionOS | n/f | n/f | too few |
| On This Day - Daily Memories (Tiny Whale), id6794757309 | viewer and cleanup | yes | no | no | in-app cleanup | n/f | n/f | n/f | n/f | n/f |
| Ayer, id6755725357 | viewer | yes, Then & Now collages | no | no | no | yes | iPad | free | n/f | n/f |
| Apple Photos (native) | native | no true same-date view | duplicates, including different resolution or format, not near-similar shots | no | Recently Deleted | Featured and Memories | all | free | none | n/a |
| Google Photos (native) | native | Memories carousel; "Rediscover this day" retired ~2020 | yes | no | trash | yes | all | free | storage | n/a |

## Per-app notes worth keeping

Swipewipe. The category's Kleenex. Competitor sites are literally structured as "Swipewipe
alternatives" and it is the app named in TikTok's "Photo Swipe Trend" coverage. Its "On This Day"
is pinned to the top of the home screen with streaks and an iOS 18 widget, and it has an
interactive memory map. Free tier is a session cap with a cooldown reported near seven hours.
Paywall is A/B tested by region, from about $20 to about $110 a year. Complaints: weekly billing
for a task you do once, crashes near 4,000 selected items, unreliable duplicate detection, a
privacy policy that allows uploads.

Slidebox. Different grammar: swipe up to trash, swipe down to favorite, tap to file into an
album. Editors' Choice, 16K ratings. One reviewer paid $9.99 for "Compare Similar Photos" and
found it was manual side-by-side, not detection. Another reports full-screen ads every few
seconds after an update and video playback that jitters.

Cleanup (BPMobile). 574K ratings and the most aggressive funnel: a 7-day trial that auto-enrolls
into $7.99 a week. Video compression and contact cleanup. Complaints include crashes every 30
seconds, "20,000 similar images" suggestions no one can review, and data-loss reports that
include contacts.

CleanMy Phone. The most polished automated cleaner and the best shrink toolkit: Live Photo to
still, five-video batch compression, AI content categories, best-shot picking. Users who came
from Gemini Photos say the successor lost similar-photo detection and got slower, which is a
live example of redesign risk.

Clever Cleaner. Made by the Disk Drill company. Free with no ads or subscriptions and 81K
ratings. One comparison site claims it added daily caps in 2026; the developer's own pages still
say fully free. Either way it is the "genuinely free" benchmark reviewers cite.

This Day. The best-executed daily-ritual cleaner: iPhone and iPad, exact duplicates, Live Photo
to still, achievements tied to storage reclaimed, streaks, reminders, $29.99 a year, and a
9to5Mac Indie App Spotlight.

Swipe & Tidy. The only ritual-group app confirmed on macOS 15 and visionOS. It routes deletes
through Recently Deleted with a mandatory review screen first. Free 50 swipes a day, $29.99
lifetime.

Swipy. No weekly plan by design, 16 languages, $29.99 lifetime. Reviewers wanted a list view of
bookmarked photos instead of one-by-one, and reported slow video handling.

Swoto. The most modes: On This Day, random, screenshots, videos, year timeline. Detects faces
(flags cropped or hidden faces) and cleans screenshots by source app.

LuminaClean. Detection tool with a daily "Daily Bites" ritual bolted on. Blur, similar,
screenshots, video compression, Live Photo to still, contact dedup. $17.99 lifetime.

On This Day Rewind. This is the Florian Grossmann app MacStories reviewed, shipped under a
different title, almost certainly because "On This Day" is taken many times over. Four widget
sizes with adjustable photo count, EXIF, a map, share with a date caption, last three years free,
$4.99 one-time. The naming lesson applies to us.

Photos On This Day and Memories: Relive Your Photos. The two viewers that let the user pick the
source: Shared Photos, shared albums, or the library. Rewind (Yang Song) reviewers asked for the
same thing at the album level. No cleaner offers it.

Timehop. 172K ratings and the only app with a documented empty-day fallback: "Nostalgic News"
trivia when you have no memories for the date. Its "Then & Now" pairing (old photo next to a new
one) is the format Ayer copied.

Apple and Google. Apple's Memories are algorithmic mixes by date, place, and people, and Apple
support tells users asking for true same-date behavior that it does not exist, which is the gap
every viewer markets against. Apple's Duplicates utility merges copies that differ in
resolution, format, or metadata, but it does not catch near-similar shots or bursts. A 9to5Mac
piece from 2026-08-28 says iOS 27 upgrades Memories in a big way; details were not retrievable
and this is the main platform risk. Google retired "Rediscover this day" into the Memories
carousel around November 2020 and community threads still ask for it back with a daily
notification across all years.

## What no one does

Across all 34 rows (32 apps and the two native platforms):

- No Lock Screen, StandBy, or Apple Watch widget was found for any app.
- No interactive widget. Every widget is a picture that opens the app.
- No documented empty-day behavior except Timehop's trivia fallback.
- No cleaner lets you scope "On This Day" to an album or a source, although two viewers do.
- No app groups a day into moments by time and place. The finest grain anywhere is "by year".
- No app labels reclaimed storage as pending until Recently Deleted is emptied.
- No app pairs the daily ritual with near-duplicate culling inside the same day. The detection
  tools scan the whole library; the ritual apps have no detection.
- No ritual app supports iPhone, iPad, and Mac with synced review state. Swipe & Tidy has the
  platforms, Sift: Organize has the sync, nobody has both.

## Unmet needs, ranked by how often they came up

From App Store review snippets, Apple and Google community threads, and comparison sites. The
"reddit" intent in this category is mostly captured by SEO content farms (Favvy, InsanelyMac,
JustUseApp), so first-person Reddit quotes were rare.

1. Near-similar and burst detection. Users say "Apple's duplicate detection only finds exact
   copies". Apple's utility does merge copies that differ in resolution or format, but a crop, a
   filter, or the next frame of a burst is never flagged. Partly met by CleanMy Phone, Clever
   Cleaner, LuminaClean, Cull. Not met by any ritual app.
2. Screenshot cleanup that leaves personal photos alone. A whole sub-genre of single-purpose
   apps exists for it.
3. Batch Live Photo to still. "There's no easy way to batch convert Live Photos" natively. Met by
   CleanMy Phone, This Day, LuminaClean, Clever Cleaner.
4. On This Day scoped to a chosen album or source. Asked for on Rewind; met only by two viewers.
5. Reversible cleanup. Undo and a review-before-commit screen are advertised as differentiators
   because users fear a bad swipe.
6. Video compression without visible loss, sharper since the iPhone 15 camera made libraries
   fill "65% faster".
7. iPad and Mac. Most swipe cleaners are iPhone only.
8. Safe handling of iCloud Shared Photo Library so a delete does not remove a family member's
   photo.
9. Calendar navigation and daily notifications in viewers that lack them.
10. A way to stop Live Photos auto-playing.

## Complaints that drive one-star reviews

1. Predatory weekly subscriptions. A 2025 investigation found cleanup apps ranked in the top 15
   free utilities charging a grandmother $7.99 a week, advertised to the elderly on Facebook and
   YouTube.
2. Crashes during bulk delete (Swipewipe near 4,000 items, Cleanup "every 30 seconds").
3. Data loss, including contacts, from the all-in-one cleaners.
4. Redesign regressions (Gemini Photos to CleanMy Phone).
5. Ads or paywalls added after an update (Slidebox).
6. Similar-photo suggestions too large to act on ("20,000 similar images").
7. Price out of proportion to a task done once ("$5+ per week for what this is").

## Triggers and switching

People arrive from the storage-full alert, a new phone with a bigger camera, iCloud upgrade
nagging, the TikTok "Photo Swipe Trend", and, for the ritual apps, the morning-coffee habit
("opening it every morning when I first wake up"). The one documented switch path is Swipewipe
to Favvy on price. MacPaw's forced Gemini to CleanMy Phone migration is the cautionary one.

## Words users search

Occurrence across 30 result sets, a proxy for volume, not a measurement:

| Phrase | Sets |
|---|---|
| photo cleaner | 24 |
| swipewipe (as a generic) | 10 |
| swipe to delete | 9 |
| on this day | 7 |
| camera roll cleaner | 6 |
| duplicate photos | 5 |
| storage cleaner | 5 |
| declutter | 4 |
| memories, relive your photos | 3 |
| screenshot cleaner | 2 |
| compress video | 2 |

## Sources

Listings: the App Store ids in the matrix. Reviews and comparisons: favvyapp.com (Swipewipe
review, alternatives, top 5), insanelymac.com (Swipewipe, Cleanup, Clever Cleaner reviews),
cleanmymac.com (Swipewipe review), tools.macgasm.net (Cleanup review), justuseapp.com (Slidebox
reviews), sourceforge.net (Slidebox), setapp.com (CleanMy Phone reviews), cultofmac.com (Clever
Cleaner), swipephotos.com (compare), luminaclean.app, macpaw.com (features, Gemini migration),
cleverfiles.com. Press: 9to5mac.com (This Day spotlight 2026-05-02; iOS 27 Photos 2026-08-28),
macstories.net (On This Day review), techcrunch.com (Swipewipe acquisition; Google Rediscover
this day 2015), screenrant.com (Photo Swipe Trend), connortumbleson.com (predatory cleanup apps,
2025-01-13), ilounge.com (similar-not-exact duplicates). Community: support.apple.com (merge
duplicates), discussions.apple.com (widget shows no content; on this day photos), support.google.com
(On This Day thread), help.timehop.com (widget).
