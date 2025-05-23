# Amnesia 🧠✨

[![CircleCI](https://circleci.com/gh/harshsbajwa/amnesia.svg?style=svg)](https://circleci.com/gh/harshsbajwa/amnesia)

Amnesia is your personal AI-powered recall assistant for macOS. It periodically captures what's on your screen, performs OCR to extract text, and allows you to chat with a local AI model that can use this captured context to answer your questions about your past activity. All processing and data storage happen on-device, prioritizing your privacy.

## Key Features

*   **Continuous Screen Capture**: Automatically captures your screen activity at configurable intervals.
*   **On-Device OCR**: Extracts text from screenshots using Apple's Vision framework.
*   **Local Data Storage**: Securely stores captured screenshots and OCR text locally using Core Data / SwiftData.
*   **AI-Powered Chat**: Interact with local Large Language Models (LLMs) via a chat interface.
*   **Contextual Recall**: The AI uses your recent screen activity as context to provide relevant answers.
*   **Model Selection**: Choose from various supported local AI models (powered by MLX).
*   **Screenshot Timeline & Gallery**: Browse your captured history visually.
*   **Configurable Capture**: Adjust capture frequency via the menu bar popover.
*   **Privacy Focused**: All data and AI processing remain on your Mac. No cloud services are used for core recall functionality (model downloads require internet).
*   **Exclusion Control**: (Advanced) Configure excluded applications or window titles via `UserDefaults` to prevent certain content from being captured.

## Technology Stack

*   **UI**: SwiftUI
*   **Core Logic**: Swift
*   **Screen Capture**: ScreenCaptureKit
*   **OCR**: Apple Vision Framework
*   **Data Persistence**: Core Data / SwiftData (using `.xcdatamodel`)
*   **Local AI Models**: [MLX Swift](https://github.com/ml-explore/mlx-swift) (utilizing models like Llama, Qwen, etc.)
*   **Dependencies**: Swift Package Manager

## Permissions Required

Amnesia requires **Screen Recording** permission to function.
*   **How to grant**:
    1.  The app will prompt you if permission is missing, or you can go to System Settings.
    2.  Navigate to **System Settings > Privacy & Security > Screen Recording**.
    3.  Find **Amnesia** in the list and enable the toggle.
    4.  You may need to restart Amnesia for the changes to take full effect.

## Getting Started / Building from Source

**Prerequisites:**
*   macOS 14.0 Sonoma or later (recommended due to ScreenCaptureKit and MLX requirements).
*   Xcode 15.3 or later.

**Steps:**
1.  Clone the repository:
    ```bash
    git clone https://github.com/harshsbajwa/amnesia.git
    cd amnesia
    ```
    *https://github.com/harshsbajwa/amnesia.git*
2.  Open the project in Xcode:
    ```bash
    xed amnesia.xcodeproj
    ```
    Alternatively, open `amnesia.xcodeproj` directly from Finder.
3.  Xcode should automatically resolve Swift Package Manager dependencies. If not, go to `File > Packages > Resolve Package Versions`.
4.  Select the `amnesia` scheme and your Mac as the run destination.
5.  Build and Run (Cmd+R).

## How to Use

1.  **Status Bar Icon**:
    *   Amnesia runs as a menu bar application.
    *   Click the icon (👁️ when capturing, 👁️‍🗨️ when paused) to open the popover.
    *   From the popover, you can:
        *   Start or Pause screen capturing.
        *   Adjust the capture interval (e.g., every 5 seconds to 120 seconds).
        *   Open the main Chat Window.
        *   Quit Amnesia.

2.  **Chat Interface**:
    *   Open the Chat Window from the popover or by reopening the app.
    *   Type your questions or prompts. The AI will use relevant context from your recent screen captures to answer.
    *   You can select different AI models from the toolbar.
    *   The system prompt (instructions for the AI) can be customized from within the chat view.

3.  **Screenshot Timeline & Gallery**:
    *   A mini-timeline of recent captures is visible at the top of the Chat Window.
    *   Access the full Screenshot Gallery from the Chat Window's toolbar (photo stack icon) to browse all captures with details.

## Configuration (Advanced)

Amnesia uses `UserDefaults` for certain configurations. You can modify these using the `defaults` command in Terminal if needed. The bundle identifier is `harshsbajwa.amnesia`.

*   **Capture Interval**:
    *   Key: `captureInterval` (Double, in seconds)
    *   Managed by the UI popover slider.
    *   Example: `defaults write harshsbajwa.amnesia captureInterval 30`
*   **OCR Recognition Level**:
    *   Key: `ocrRecognitionLevel` (String, "accurate" or "fast")
    *   Example: `defaults write harshsbajwa.amnesia ocrRecognitionLevel "fast"`
*   **Excluded App Bundle IDs**:
    *   Key: `excludedAppBundleIDs` (Array of Strings)
    *   Example: `defaults write harshsbajwa.amnesia excludedAppBundleIDs -array "com.apple.Terminal" "com.example.privateapp"`
*   **Excluded Window Title Keywords**:
    *   Key: `excludedWindowTitleKeywords` (Array of Strings, case-insensitive match)
    *   Example: `defaults write harshsbajwa.amnesia excludedWindowTitleKeywords -array "password" "secret-project"`
*   **Ignore Incognito Windows**:
    *   Key: `ignoreIncognitoWindows` (Boolean, true/false)
    *   Looks for "incognito", "private browsing", "inprivate" in window titles.
    *   Example: `defaults write harshsbajwa.amnesia ignoreIncognitoWindows -bool true`

*Note: Restart Amnesia after changing `UserDefaults` via command line for them to take full effect, especially for exclusion rules.*

## CI/CD

Continuous Integration is set up using CircleCI. The configuration can be found in `.circleci/config.yml`. Builds are triggered on pushes to the `main` branch.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request or open an Issue for bugs, feature requests, or suggestions.