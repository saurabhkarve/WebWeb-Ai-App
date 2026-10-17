{{flutter_js}}
{{flutter_build_config}}

// Color emoji for reactions (❤️ 👍 🙏): without this the web renderer draws them with a
// black-and-white emoji font, so a ❤️ reaction looks like a filled black heart.
_flutter.loader.load({
  config: { useColorEmoji: true },
});
