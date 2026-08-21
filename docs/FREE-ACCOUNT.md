# Running Morse on a free Apple Developer account

You do not need the $99/yr Apple Developer Program to use Morse — but the free tier has
real limitations you'll live with:

| Limitation | Effect |
|---|---|
| Provisioning profiles last **7 days** | The app refuses to launch after a week. Plug in (or use Wi-Fi debugging) and press Run in Xcode to re-install. Your data, settings, and the downloaded model **persist** — only the signature is refreshed. |
| Max **3 sideloaded apps** | AXAssistant is 1; the WDA runner (AXDriver) is 2. |
| Max 10 App IDs per 7 days | Don't churn bundle identifiers. |
| Restricted entitlements | No push notifications, no WeatherKit, no `increased-memory-limit`. Morse is designed to need none of these. |

## The weekly ritual

1. Connect the iPhone (cable or same-Wi-Fi with wireless debugging enabled).
2. Open the project in Xcode, press **⌘R** once.
3. Done — everything (model weights, history, settings) is exactly as you left it.

If you later join the paid program, nothing changes except signatures last a year and
TestFlight/App Store distribution of AXAssistant becomes possible.
