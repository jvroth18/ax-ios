# Setting up WebDriverAgent on your iPhone (free developer account)

WDA is maintained by the Appium project: <https://github.com/appium/WebDriverAgent>.
Use **v11.4.1 or newer** (iOS 26 support).

## One-time setup

1. Clone it:
   ```bash
   git clone https://github.com/appium/WebDriverAgent
   open WebDriverAgent/WebDriverAgent.xcodeproj
   ```
2. In Xcode, select the **WebDriverAgentRunner** target → Signing & Capabilities:
   - Team: your Personal Team
   - Change the bundle identifier to something unique, e.g. `dev.yourname.wdarunner`
     (free accounts can't use the Appium default).
3. Select your iPhone as the destination, then **Product → Test** once. This installs
   `WebDriverAgentRunner-Runner` on the phone. Stop the test after it starts.
4. On the phone, trust the developer cert (Settings → General → VPN & Device Management).

## Starting the runner (each session)

The documented "preinstalled runner" flow — from your Mac:

```bash
# Find the device id
xcrun devicectl list devices

# Launch the runner app; it starts the WDA HTTP server on port 8100
xcrun devicectl device process launch --device <DEVICE-ID> dev.yourname.wdarunner.xctrunner
```

Verify from Safari **on the phone**: `http://127.0.0.1:8100/status` should return JSON
with `"ready": true`.

## Weekly ritual (free account)

The provisioning profile expires after 7 days. Re-run step 3 (Product → Test) to
re-install, then launch as above. A paid account ($99/yr) extends this to one year.
