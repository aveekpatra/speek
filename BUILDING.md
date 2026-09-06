# Building Whisper Pro

This guide provides detailed instructions for building Whisper Pro from source.

## Prerequisites

Before you begin, ensure you have:
- macOS 14.4 or later
- Xcode (latest version recommended)
- Swift (latest version recommended)
- Git (for cloning repositories)
- CMake 3.28.0 or later, needed to build whisper.cpp: `brew install cmake`

## Quick Start with Makefile (Recommended)

The easiest way to build Whisper Pro is using the included Makefile, which automates the entire build process including building and linking the whisper framework.

### Simple Build Commands

```bash
# Clone the repository
git clone https://github.com/ZdenekCulik/whisper-pro.git
cd whisper-pro

# Build everything (recommended for first-time setup)
make all

# Or for development (build and run)
make dev
```

### Available Makefile Commands

- `make check` or `make healthcheck` - Verify all required tools are installed
- `make whisper` - Clone and build whisper.cpp XCFramework automatically
- `make setup` - Prepare the whisper framework for linking
- `make build` - Build the Whisper Pro Xcode project
- `make local` - Build for local use (no Apple Developer certificate needed)
- `make signed` - Stable signed dev build, installed to /Applications (survives rebuilds without re-granting Accessibility/Microphone permissions)
- `make dmg` - Build a distributable DMG (`dist/WhisperPro-<version>.dmg`) for sharing the app with someone else
- `make run` - Launch the built Whisper Pro app
- `make dev` - Build and run (ideal for development workflow)
- `make all` - Complete build process (default)
- `make clean` - Remove build artifacts and dependencies
- `make help` - Show all available commands

### How the Makefile Helps

The Makefile automatically:
1. **Manages Dependencies**: Creates a dedicated `~/WhisperPro-Dependencies` directory for all external frameworks
2. **Builds Whisper Framework**: Clones whisper.cpp and builds the XCFramework with the correct configuration
3. **Handles Framework Linking**: Sets up the whisper.xcframework in the proper location for Xcode to find
4. **Verifies Prerequisites**: Checks that git, xcodebuild, and swift are installed before building
5. **Streamlines Development**: Provides convenient shortcuts for common development tasks

This approach ensures consistent builds across different machines and eliminates manual framework setup errors.

---

## Building for Local Use (No Apple Developer Certificate)

If you don't have an Apple Developer certificate, use `make local`:

```bash
git clone https://github.com/ZdenekCulik/whisper-pro.git
cd whisper-pro
make local
open ~/Downloads/Whisper Pro.app
```

This builds Whisper Pro with ad-hoc signing using a separate build configuration (`LocalBuild.xcconfig`) that requires no Apple Developer account.

### How It Works

The `make local` command uses:
- `LocalBuild.xcconfig` to override signing and entitlements settings
- `WhisperPro.local.entitlements` (stripped-down, no CloudKit/keychain groups)
- `LOCAL_BUILD` Swift compilation flag for conditional code paths

Your normal `make all` / `make build` commands are completely unaffected.

---

## Stable Signed Dev Build (`make signed`)

Ad-hoc signed builds (`make local`) get a new signature on every rebuild, so macOS makes
you re-grant Accessibility and Microphone permissions each time. `make signed` fixes that
by signing with your own Apple Development certificate and installing to
`/Applications/Whisper Pro.app` — same signature every time, so permissions granted once
survive future rebuilds.

```bash
make signed
```

To use your own certificate (instead of the placeholder), create an untracked
`Makefile.local` in the repo root:

```make
SIGN_IDENTITY := Apple Development: you@example.com (YOURTEAMID)
DEV_TEAM := YOURTEAMID
```

Find your identity with `security find-identity -v -p codesigning`. `Makefile.local` is
gitignored, so your personal signing identity never ends up in the repo.

## Distributable DMG (`make dmg`)

To build a `.dmg` you can hand to someone else:

```bash
make dmg
```

By default this reuses your `SIGN_IDENTITY` (Apple Development), which is enough to
produce a runnable DMG — the other person just has to right-click → "Open Anyway" past
Gatekeeper once. If you have a paid Apple Developer Program membership, set your own
`DIST_IDENTITY` in `Makefile.local` for a proper Developer ID + notarized build:

```make
DIST_IDENTITY := Developer ID Application: You (YOURTEAMID)
```

See `scripts/make-dmg.sh` for the full packaging pipeline.

---

## Manual Build Process (Alternative)

If you prefer to build manually or need more control over the build process, follow these steps:

### Building whisper.cpp Framework

1. Clone and build whisper.cpp:
```bash
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
./build-xcframework.sh
```
This will create the XCFramework at `build-apple/whisper.xcframework`.

### Building Whisper Pro

1. Clone the Whisper Pro repository:
```bash
git clone https://github.com/ZdenekCulik/whisper-pro.git
cd whisper-pro
```

2. Add the whisper.xcframework to your project:
   - Drag and drop `../whisper.cpp/build-apple/whisper.xcframework` into the project navigator, or
   - Add it manually in the "Frameworks, Libraries, and Embedded Content" section of project settings

3. Build and Run
   - Build the project using Cmd+B or Product > Build
   - Run the project using Cmd+R or Product > Run

## Development Setup

1. **Xcode Configuration**
   - Ensure you have the latest Xcode version
   - Install any required Xcode Command Line Tools

2. **Dependencies**
   - The project uses [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for transcription
   - Ensure the whisper.xcframework is properly linked in your Xcode project
   - Test the whisper.cpp installation independently before proceeding

3. **Building for Development**
   - Use the Debug configuration for development
   - Enable relevant debugging options in Xcode

4. **Testing**
   - Run the test suite before making changes
   - Ensure all tests pass after your modifications

## Troubleshooting

If you encounter any build issues:
1. Clean the build folder (Cmd+Shift+K)
2. Clean the build cache (Cmd+Shift+K twice)
3. Check Xcode and macOS versions
4. Verify all dependencies are properly installed
5. Make sure whisper.xcframework is properly built and linked

For more help, please check the [issues](https://github.com/ZdenekCulik/whisper-pro/issues) section or create a new issue. 

## Release build

```bash
scripts/release-build.sh
```

Produces `dist/Speek-<version>.zip`. Without a Developer ID it is ad-hoc signed and
users must right-click > Open on first launch. With an Apple Developer account:

```bash
SIGN_ID="Developer ID Application: Your Name (TEAMID)" NOTARIZE=1 KEYCHAIN_PROFILE=speek-notary scripts/release-build.sh
```

(`xcrun notarytool store-credentials speek-notary` once to save the App Store Connect API key.)
