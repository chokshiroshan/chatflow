# Homebrew Cask formula for ChatFlow
# To submit: fork homebrew-cask, add this to Casks/chatflow.rb, PR it
#
# Users can install with:
#   brew install --cask chatflow
#
# Or without submitting to homebrew-cask, users can install directly:
#   brew install --cask ./chatflow.rb

cask "chatflow" do
  version "1.0.0"
  sha256 "REPLACE_WITH_ACTUAL_SHA256"

  url "https://github.com/chokshiroshan/chatflow/releases/download/v#{version}/ChatFlow.dmg",
      verified: "github.com/chokshiroshan/chatflow/"
  name "ChatFlow"
  desc "Voice dictation app powered by OpenAI's Realtime API"
  homepage "https://github.com/chokshiroshan/chatflow"

  depends_on macos: ">= :sonoma"

  app "ChatFlow.app"

  zap trash: [
    "~/Library/Preferences/ai.flow.app.plist",
    "~/Library/Caches/ai.flow.app",
    "~/Library/Application Support/ChatFlow",
  ]

  caveats <<~EOS
    ChatFlow requires the following permissions:
      • Microphone — for voice dictation
      • Accessibility — for global hotkey and text injection
      • Input Monitoring — for keyboard event handling

    Grant these in System Settings → Privacy & Security.

    On first launch, right-click ChatFlow.app → Open to bypass Gatekeeper.
    (Required until the app is notarized with an Apple Developer certificate.)
  EOS
end
