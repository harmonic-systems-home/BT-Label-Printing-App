# BTLabel — App Privacy questionnaire (App Store Connect)

App Store Connect → your app → **App Privacy**.

## Top-level answer
**"Do you or your third-party partners collect data from this app?" → No.**

This yields a **"Data Not Collected"** privacy label. That is accurate for BTLabel,
for the reasons below. (Apple defines "collect" as transmitting data off the device
in a way you or your partners can access.)

## Why "Not Collected" is correct
- **iCloud sync (favorites, folders, history, contact fields):** stored in the
  user's **private CloudKit database**. Apple's guidance is explicit that data in a
  user's private CloudKit database that the developer **cannot access** does not need
  to be disclosed and is not considered developer "collection." BTLabel has no
  server and never receives this data.
- **Contact fields (name, phone, street, email):** entered by the user to fill label
  tokens, stored locally + in their private iCloud. Never sent to the developer.
- **Purchases:** processed by **Apple** via StoreKit. The developer receives only
  Apple's aggregated sales reports, which don't identify individuals. Apple's own
  data handling is not something you disclose here.
- **No analytics, no advertising, no tracking, no third-party SDKs** in the app.
- **Bluetooth:** used only to talk to the label printer; nothing leaves the Mac
  except to the printer (and the user's own iCloud).

## If Apple asks follow-ups / for confidence
- **Tracking:** No. (No data is used to track users across apps/websites.)
- **Third-party partners:** None.
- **Support email:** If a user emails support@btlabel.org, that happens outside the
  app and isn't data "collected from the app," so it isn't disclosed here.

## Keep consistent with
- Published privacy policy: https://btlabel.org/privacy.html
- These answers must match the policy — both say: no collection, iCloud-only,
  no analytics/tracking/third parties.
