# Home Library

A cosy pink iPhone app for cataloguing the books on your shelves.

- **Scan books** with the camera: point it at the barcode on the back cover. The title, author, year and cover are filled in from Open Library, with Google Books as a fallback.
- **Track reading**: To be read, Reading, or Read (with the date you finished).
- **Track purchases**: when you bought it, the price, and where from.
- **Track loans**: who borrowed it and when, plus a history of past loans.
- Filter by Owned / Read / To be read / Lent out, search, and sort.
- Catches duplicate ISBNs and typos (check-digit validation).

Everything is stored on the phone with SwiftData. No account is needed.

## Requirements

- Xcode 16 or later
- iOS 17 or later

## Run it on your iPhone

1. Open `HomeLibrary.xcodeproj` in Xcode.
2. Select the **HomeLibrary** target, open **Signing & Capabilities**, and choose your Apple ID under **Team**. If Xcode says the bundle identifier is taken, change it to something unique, e.g. `com.yourname.HomeLibrary`.
3. Plug in your iPhone and pick it as the run destination.
4. Press **Run** (⌘R).
5. On the iPhone, go to **Settings → General → VPN & Device Management** and trust your developer certificate.

With a free Apple ID, the app keeps working for 7 days before it needs reinstalling from Xcode. A paid Apple Developer account removes that limit.

The barcode scanner needs a real iPhone. In the simulator you can type an ISBN instead.

## Web version

`web/home-library.html` is the claude.ai web version of the same catalog.
