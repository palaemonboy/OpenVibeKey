# Open VibeKey

<p>
  <a href="https://github.com/palaemonboy/OpenVibeKey/stargazers"><img src="https://img.shields.io/github/stars/palaemonboy/OpenVibeKey?style=flat&logo=github" alt="GitHub stars"></a>
  <a href="https://github.com/palaemonboy/OpenVibeKey/releases/latest"><img src="https://img.shields.io/github/v/release/palaemonboy/OpenVibeKey?display_name=release&logo=github" alt="Latest release"></a>
  <a href="https://openvibekey.palaemon.dev"><img src="https://img.shields.io/badge/website-openvibekey.palaemon.dev-0A66C2?logo=googlechrome&logoColor=white" alt="Open VibeKey website"></a>
  <a href="#license"><img src="https://img.shields.io/github/license/palaemonboy/OpenVibeKey" alt="MIT license"></a>
  <a href="README.zh-CN.md"><img src="https://img.shields.io/badge/%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87-README-1677FF" alt="简体中文"></a>
</p>

**English** | [简体中文](README.zh-CN.md)

Make your VibeKey work your way on macOS.

Open VibeKey is a free, open-source macOS app for Ulanzi AU05 Vibe Key. Customize the dial and buttons, adjust lighting and microphone settings, and choose your Mac’s audio input—all from a settings window and a menu bar panel.

Buy the device: [Ulanzi AU05 Vibe Key](https://www.ulanzi.com/products/au05-vibe-key-ai-voice-input-keypad-i018).

![Open VibeKey settings and menu bar panel — English interface preview](assets/screenshots/open-vibekey-en.png)

*Interface preview with sample settings.*

## Requirements

- macOS 13 or later.
- A Ulanzi AU05 Vibe Key and its receiver for device controls.

## Installation

Install with Homebrew:

```sh
brew install --cask palaemonboy/tap/openvibekey
```

## How to use

1. Connect the receiver to your Mac and turn on your VibeKey.
2. Open Open VibeKey, then click its icon in the menu bar.
3. Choose **Open Settings…** to customize the dial, buttons, lighting, and microphone.
4. In the menu bar panel, select an input device. Click its lock icon to keep it selected as your Mac’s audio input.
5. Enable **Launch at Login** if you want Open VibeKey available whenever you sign in.

Open VibeKey stays in the menu bar, so it does not appear in the Dock.

## Features

- **Custom shortcuts:** Assign keyboard shortcuts or media actions to the buttons, dial turns, and dial press.
- **Open apps:** Use a button or the dial press to launch or switch to a chosen app.
- **Profiles:** Save different setups and switch between them from the menu bar.
- **Double-click the dial to switch profiles:** Enabled by default. Press the dial twice within the interval to cycle through saved profiles and receive a notification, without triggering the single-click action. A single click waits until the interval expires before performing its original action. Use the up/down buttons to adjust the global interval in 0.1 s steps (default 0.5 s; range 0.1–1 s); changes save automatically. Requires Accessibility access and the app running in the background, even with the main window closed. Other buttons and dial rotation are unchanged.
- **Lighting controls:** Adjust global lighting, brightness, and individual lights in Work mode.
- **Microphone controls:** Toggle the device microphone, choose a noise-reduction level, and adjust input volume.
- **Audio input selection:** Switch between your VibeKey microphone, your Mac’s built-in microphone, and other available inputs. Lock your preferred input to prevent unwanted switching.
- **Device status:** Check connection status, battery level, and firmware information.
- **Launch at login:** Keep your controls close at hand after signing in.

## Good to know

- Ordinary keyboard shortcuts saved to the device continue to work after you quit Open VibeKey. **Open App** actions require Open VibeKey to remain running.
- Open App bindings can conflict with shortcuts used by other software. If an action does not respond, check for shortcut conflicts.
- Grant microphone access from the startup permission window to use the live input level meter.
- Device controls require the AU05 to be powered on; connecting the receiver alone is not enough.

## Double-click profile switching

**Double-click dial to switch profiles** is always enabled; there is no toggle. A single press waits for the configurable interval (default 0.5 s, range 0.1–1 s, adjusted with up/down buttons and saved automatically) before executing its existing action; a double press only switches profiles and sends a notification. Other buttons and dial rotation keep their existing behavior. Accessibility access is required to replay delayed shortcuts and media keys.

At startup, a unified window checks Accessibility, microphone and notification permissions. Each Settings button opens the corresponding system pane; polling never opens System Settings or requests access. The window can only close after all permissions are granted, but Quit remains available. Newly completed authorization opens the main window directly when access is already effective. Only stale in-process permission state requires one restart, followed by opening the main window. Closing the main window keeps the menu-bar listener running. Notifications acknowledge switching immediately and confirm the result after device writes finish.

The app temporarily takes over the dial press while enabled, preserving the original single action in each profile. Quitting normally restores the device setting. Failed restoration is reported before quitting; after a force quit or crash, reconnect and launch the app to recover.

Quit the installed app from the menu bar before opening the development build so only one app controls the device. Device settings are still shared hardware state. Quit the development build before returning to the installed app.

## Project Structure

```text
.
├── native/VibeKit/       # Native macOS app
│   ├── Package.swift     # Project configuration
│   └── Sources/         # App interface, device controls, resources, and tests
├── assets/screenshots/  # English and Chinese interface previews
├── landing/             # Project website
├── scripts/             # App packaging and localization checks
├── README.md            # English introduction
├── README.zh-CN.md       # Chinese introduction
└── LICENSE              # MIT license
```

## Feedback

Found a problem or have a suggestion? [Open an issue](https://github.com/palaemonboy/OpenVibeKey/issues) and include your macOS version, device firmware version, and what happened.

## License

[MIT](LICENSE) © 2026 palaemonboy.

If you build on this project, a link back to [Open VibeKey](https://github.com/palaemonboy/OpenVibeKey) is appreciated. This is a voluntary request, not an additional license condition.
