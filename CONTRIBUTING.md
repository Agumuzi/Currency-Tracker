# Contributing to Currency Tracker

Thanks for helping improve Currency Tracker, a local-first macOS menu bar utility.

## Before filing an issue

Search [existing issues](https://github.com/Agumuzi/Currency-Tracker/issues). For a bug, provide the app version, macOS version, architecture, interface language, provider (if relevant), and reproducible steps. Never share API keys, exported settings containing credentials, or sensitive user data.

For a potential vulnerability, follow [SECURITY.md](SECURITY.md) rather than posting details in public.

## Pull requests

1. Open an issue first for large or behavior-changing proposals.
2. Keep changes focused and avoid unrelated UI, refactor, and dependency changes.
3. Check `.github/workflows/ci.yml` for the repository's actual build and test commands.
4. Run relevant localization checks and tests, especially for changes in settings, updates, import/export, or global selection handling.
5. Include a clear description, test results, affected macOS versions, and screenshots for UI changes.
6. Do not commit personal provider credentials, signing keys, real user settings, or unlicensed third-party assets.

Please preserve the project's existing release/versioning and Homebrew distribution workflow unless a change explicitly requires modifying it.

## License

The original project-maintained source code is licensed under the [MIT License](LICENSE), permitting commercial and noncommercial reuse with the required notices. Original application icons, logos and screenshots are reserved under the [Brand & Visual Assets notice](ASSETS-LICENSE.md); third-party assets follow their own terms.

Only submit contributions you have the right to distribute under MIT. Contributors retain their copyrights; a pull request does not automatically transfer copyright or permit relicensing under unrelated terms without appropriate permission.
