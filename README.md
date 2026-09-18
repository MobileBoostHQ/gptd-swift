# gptd-swift

A Swift package to utilize GPT Driver for executing commands on iOS devices.

## Overview

**gptd-swift** provides a convenient way to execute natural language commands via GPT Driver on your app. It runs either directly against XCUITest or through a remote Appium server. It's designed for developers who want to integrate these capabilities into their iOS projects.

## Features

- **Session Management:** Automatically starts and manages sessions.
- **Screenshot Capture:** Uses built-in iOS APIs to capture and process screenshots.
- **Command Execution:** Based on natural language instructions and screenshots executes commands on the device.
- **Native-First Execution:** Run your own XCUITest code with automatic AI fallback when it fails.
- **Assertions and Extraction:** Verify screen state and pull values off the screen in natural language.

## Installation

Add this package in Xcode by navigating to **File > Swift Packages > Add Package Dependency** and entering the repository URL

## Usage

Reach out to us at [mobileboost.io](https://mobileboost.io) to get your API key.

All methods are synchronous and throwing, so call them with `try` from your test methods.

### Setup

```swift
import gptd_swift
import XCTest

final class MyUITests: XCTestCase {
    let app = XCUIApplication()
    var gptDriver: GptDriver!

    override func setUpWithError() throws {
        app.launch()
        gptDriver = GptDriver(apiKey: "YOUR_API_KEY", nativeApp: app)
    }
}
```

To drive a device through a remote Appium server instead:

```swift
let gptDriver = GptDriver(
    apiKey: "YOUR_API_KEY",
    appiumServerUrl: URL(string: "http://localhost:4723")!,
    deviceName: "iPhone 15 Pro",
    platform: "iOS",
    platformVersion: "18.2"
)
```

The live session URL is printed on session creation and is also available via `gptDriver.sessionURL` or the `onSessionCreated` callback.

It is also recorded as an XCTest activity, so it appears in the `xcodebuild` log and in the `.xcresult` on simulators, physical devices and device farms such as Firebase Test Lab, where the test runner's stdout is not captured:

```
t =    12.34s GPTDriver Live Session URL: https://app.mobileboost.io/gpt-driver/sessions/<id>
...
t =    98.76s GPTDriver Session success: https://app.mobileboost.io/gpt-driver/sessions/<id>
```

On Buildkite, grep the xcodebuild output for `GPTDriver Live Session URL` and pass the match to `buildkite-agent annotate` to surface it at the top of the build.

### Executing commands

```swift
try gptDriver.execute("Tap the first 'Add to Cart' button")
```

### Native-first execution with AI fallback

Pass a `nativeAction` closure to run your own XCUITest code first. If it succeeds, the step is recorded and the test moves on without an AI round trip. If it throws, raises an Objective-C exception, or hits a failing `XCTAssert`, the SDK falls back to executing the natural language command with AI.

```swift
func searchFor(_ query: String) throws {
    try gptDriver.execute("Tap on Search, type '\(query)', and submit", nativeAction: {
        let searchField = app.textFields["Navigation.TopNav.SearchBar.Input.Aid"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 15))
        searchField.tap()
        searchField.typeText(query)
        app.keyboards.buttons["Search"].tap()
    })
}
```

XCTest assertion failures inside the closure are intercepted and are **not** recorded as test failures, since the AI fallback takes over. Only a failure of the fallback itself fails the test.

The natural language command is not just a fallback, it is also the label the step carries in the session recording, so keep it descriptive of what the native code does.

`nativeAction` works the same way for assertions and checks:

```swift
try gptDriver.assert("Verify 'Haul Away' option is visible", nativeAction: {
    XCTAssertTrue(app.staticTexts["Haul Away"].waitForExistence(timeout: 5))
})

try gptDriver.assertBulk([
    "The subtotal is visible",
    "The grand total is visible"
], nativeAction: {
    XCTAssertTrue(app.staticTexts["Subtotal"].exists)
    XCTAssertTrue(app.staticTexts["Grand Total"].exists)
})

// If the closure succeeds, every condition is reported as true.
let results = try gptDriver.checkBulk(["Cart badge shows 1"], nativeAction: {
    XCTAssertEqual(app.buttons["TabBar.Cart.Aid"].value as? String, "1")
})
```

#### Native steps in the session recording

Successful `nativeAction` blocks are reported to the GPT Driver backend so they appear as steps in the session recording alongside AI-driven steps. Each report captures and uploads a screenshot taken just before the closure runs.

Reporting is best-effort telemetry. If the screenshot or the upload fails, a warning is logged and the test continues.

For tests with many native steps, the per-step screenshot and upload is the main cost of this visibility. Turn it off to trade the session recording for speed:

```swift
let gptDriver = GptDriver(
    apiKey: "YOUR_API_KEY",
    nativeApp: app,
    logNativeExecutions: false
)
```

With `logNativeExecutions: false`, native blocks still run and still fall back to AI on failure, they just leave no entry in the session. Steps that run via the AI fallback are always recorded regardless of this flag.

### Assertions and extraction

```swift
try gptDriver.assert("The cart shows one item")

try gptDriver.assertBulk([
    "The subtotal equals $499",
    "Grand Total is correctly calculated"
])

let results = try gptDriver.checkBulk(["A promo banner is visible"])

let costs = try gptDriver.extract(["cost of item", "cost of haul away"])
let itemCost = costs["cost of item"]
```

`assert` and `assertBulk` fail the test when a condition is not met. `checkBulk` returns the results instead so you can branch on them.

### Session status

```swift
try gptDriver.setSessionSucceeded()
try gptDriver.setSessionFailed()
```

Assertion failures mark the session as failed automatically.

### Typing

The SDK types text one character at a time, pausing between characters so that apps doing work on every keystroke can keep up. Without that pause, apps can drop characters when keystrokes arrive faster than they are processed, and a 10-digit value ends up only partially entered. Text fields with a formatting delegate, and React Native or Flutter inputs crossing a bridge, are the most affected.

The default is 10 characters per second. Lower it if characters still go missing, which is most likely on slow or heavily loaded devices such as those in cloud device farms:

```swift
let gptDriver = GptDriver(
    apiKey: "YOUR_API_KEY",
    nativeApp: app,
    charactersPerSecond: 5
)
```

The pause falls between characters rather than after each one, so typing costs `(length - 1) / charactersPerSecond` seconds. At the default rate a 10-character entry adds roughly 0.9 seconds.

Pass `nil` to type each string in a single `typeText` call instead:

```swift
let gptDriver = GptDriver(
    apiKey: "YOUR_API_KEY",
    nativeApp: app,
    charactersPerSecond: nil
)
```

That is faster and is how the SDK behaved before this setting existed, but it is also what causes the dropped characters described above.

### Caching

Pass a `CachingMode` to reuse previously recorded interactions instead of querying the AI on every step:

```swift
let gptDriver = GptDriver(
    apiKey: "YOUR_API_KEY",
    nativeApp: app,
    cachingMode: .interactionRegion,
    testId: "add-to-cart-haul-away"
)
```

Available modes are `.none` (default), `.interactionRegion`, and `.fullScreen`. `execute` accepts a `cachingMode` argument to override the mode for a single step. Setting `testId` improves cache matching across runs of the same test.

### Session metadata

Pass `metadata` to record your own key/values on the session - anything your CI knows and the SDK does not:

```swift
let gptDriver = GptDriver(
    apiKey: "YOUR_API_KEY",
    nativeApp: app,
    metadata: [
        "branch": ProcessInfo.processInfo.environment["BUILDKITE_BRANCH"] ?? "unknown",
        "job": ProcessInfo.processInfo.environment["BUILDKITE_JOB_ID"] ?? "unknown"
    ]
)
```

Nothing in the SDK or the backend interprets these. They are stored on the session so a run can be found again, and so reporting can be sliced by them - failure rates on `master` only, say. Keys are free-form, values are strings; `language` and `version` are reserved for the SDK's own identity and cannot be overridden.

## License

This project is licensed under the Business Source License. See the LICENSE file for details.
