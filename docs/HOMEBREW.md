# Homebrew installation and tap migration

The Homebrew Cask for **Currency Tracker** is maintained in this repository at [`Casks/currency-tracker.rb`](../Casks/currency-tracker.rb). It downloads the macOS app directly from this project's [GitHub Releases](https://github.com/Agumuzi/Currency-Tracker/releases) and checks its SHA256 checksum.

> **Repository migration:** The previous tap repository (`Agumuzi/homebrew-currency-tracker`) is being retired. This project's repository name does not start with `homebrew-`, so the tap must be registered with an explicit Git URL. A one-argument `brew tap agumuzi/currency-tracker` will continue looking for the old repository.

## New installation

```bash
brew tap agumuzi/currency-tracker https://github.com/Agumuzi/Currency-Tracker.git
brew install --cask agumuzi/currency-tracker/currency-tracker
```

Explicitly specifying the tap and Cask avoids ambiguity if another tap contains an item with the same name.

## Migrate an existing installation

If you previously used the separate Homebrew tap, change the existing tap's Git remote **before the old repository is deleted**:

```bash
brew tap --custom-remote agumuzi/currency-tracker https://github.com/Agumuzi/Currency-Tracker.git
brew update
brew upgrade --cask agumuzi/currency-tracker/currency-tracker
```

This keeps the logical tap name (`agumuzi/currency-tracker`); it only changes the repository Homebrew uses to fetch the Cask. You do not need to uninstall the application or erase its local data.

To check the current tap, run:

```bash
brew tap-info agumuzi/currency-tracker
brew info --cask agumuzi/currency-tracker/currency-tracker
```

## Upgrade or uninstall

```bash
brew update
brew upgrade --cask agumuzi/currency-tracker/currency-tracker
```

To uninstall the app while keeping your data:

```bash
brew uninstall --cask agumuzi/currency-tracker/currency-tracker
```

The Cask also provides a `--zap` option, which removes saved support files. **Do not use `--zap` if you want to keep preferences or other local data.**

## First launch

Release builds are ad-hoc signed, not signed with an Apple Developer ID or notarized by Apple. macOS may require approval under **System Settings → Privacy & Security → Open Anyway**.

Removing quarantine manually should only be considered after verifying the download source. See the [main README](../README.md#first-launch-approval) for details.

## Release maintenance

The [release workflow](../.github/workflows/release.yml) publishes the app ZIP and SHA256 checksum, then updates the Cask in the default branch using [`scripts/update-homebrew-cask.py`](../scripts/update-homebrew-cask.py).

- Only the newest published release is eligible for the Cask update.
- The updater rejects malformed checksums and skips downgrades.
- The Git push must be a fast-forward; a concurrent change cannot be overwritten.

The original Homebrew tap's separate commit history is not imported; its Cask and installation guidance are maintained here going forward.
