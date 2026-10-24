cask "currency-tracker" do
  version "1.8.1"
  sha256 "9ac9df19ebecc6e7aa308252c2bc0fed6018987485db592a8e2c8277337c6b4d"

  url "https://github.com/Agumuzi/Currency-Tracker/releases/download/v#{version}/Currency-Tracker-#{version}.zip"
  name "Currency Tracker"
  desc "macOS menu bar app for exchange rates and quick currency conversion"
  homepage "https://github.com/Agumuzi/Currency-Tracker"

  livecheck do
    url "https://github.com/Agumuzi/Currency-Tracker/releases/latest"
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "Currency Tracker.app"

  uninstall quit: "com.thomas.Currency-Tracker"

  zap trash: [
    "~/Library/Application Support/CurrencyTracker",
    "~/Library/Caches/Currency Tracker",
    "~/Library/Preferences/com.thomas.Currency-Tracker.plist",
  ]
end
