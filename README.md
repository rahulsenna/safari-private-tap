## Flickognito: One-Tap Private Browsing for Safari

A lightweight, high-performance background daemon for macOS that adds a custom trackpad gesture to Safari. It allows you to open any link in a **Private Window** with a simple **3-finger tap**, bypassing clunky keyboard modifiers.

---

### **Essential Trackpad & Pointer Settings**

For this daemon to function without interference from macOS system gestures, you **must** configure your pointer settings exactly as follows:

#### **1. Disable 3-Finger Look Up**
macOS defaults 3-finger taps to "Look up & data detectors." This will swallow the gesture before the daemon can see it.
* Go to **System Settings > Trackpad > Point & Click**.
* Change **Look up & data detectors** to **"Force Click with One Finger"** or turn it off entirely.

#### **2. Disable Three Finger Drag**
This is the most common cause of "phantom left clicks." When enabled, macOS buffers all multi-touch input to check for a drag, which often results in a standard click being fired alongside the gesture.
* Go to **System Settings > Accessibility > Pointer Control**.
* Click **Trackpad Options...**
* Ensure **Use trackpad for dragging** is **OFF** (or set to "Without Drag Lock" using 1 finger).

#### **3. Tap to Click (Optional but Recommended)**
While the daemon works with physical clicks, it is optimized for "Tap to click" for a faster, more fluid feel.
* Go to **System Settings > Trackpad > Point & Click**.
* Toggle **Tap to click** to **ON**.

---

### **Installation & Security**

#### **Compilation**
Compile the binary using the private `MultitouchSupport` framework:
```bash
clang -F/System/Library/PrivateFrameworks -framework MultitouchSupport -framework Foundation -framework AppKit -framework CoreGraphics main.m -o SafariPrivateGesture
```

#### **Permissions (TCC)**
Because the daemon synthesizes keystrokes, you must manually whitelist the binary:
1.  Open **System Settings > Privacy & Security**.
2.  In **Accessibility**, add the `SafariPrivateGesture` binary and toggle it **ON**.
3.  In **Input Monitoring**, add the `SafariPrivateGesture` binary and toggle it **ON**.

> **Note:** If you recompile the code, you must remove and re-add the binary in these settings, as the file hash will have changed.

#### **Persistence**
Load the provided `.plist` into `launchd` to ensure the daemon runs automatically on startup:
```bash
launchctl load ~/Library/LaunchAgents/com.custom.safariprivate.plist
```

---

### **How it Works**
* **Scope:** The daemon uses an `NSWorkspace` observer to stay dormant unless Safari is the frontmost application.
* **Execution:** Detects a 3-finger tap (with a 2% drift threshold to ignore swipes) and executes: `Right Click` -> `Down` -> `Down` -> `Hold Option` -> `Enter`.