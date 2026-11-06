# Contributing

Thanks for wanting to help! This started as a tool for one dyslexic developer, and the
goal is to make it useful for anyone who'd rather listen than read. Small fixes,
big ideas, and "this didn't work on my machine" reports are all welcome.

## Ways to help

- **Report a problem.** Open an issue and say what you did, what you expected, and what
  happened. Include your Windows version, your Claude Code version, and the last lines
  of `%TEMP%\claude-voice\voice.log`.
- **Suggest an idea.** Open an issue describing what you'd like and why it would help.
- **Send a fix.** Fork the repo, make your change on a branch, and open a pull request.
  Keep it focused on one thing and explain what you tested.

## Most wanted

1. **Hands-free microphone that actually works.** See `experimental/hands-free-mic/`.
   The open problem is echo: on laptop speakers, scraps of the reader's voice leak into
   the mic. Windows voice typing (Win+H) doesn't have this problem, probably because it
   uses the audio driver's own echo cancelling for "communications" capture. Trying
   WASAPI capture with `AudioCategory_Communications` is the most promising next step.
2. **Configurable hotkeys.** Ctrl+Alt+letter is AltGr on many non-US keyboards.
3. **One reader per session.** Today every Claude Code session shares one reader.
4. **Other voices and platforms.** A fully offline neural voice (for example Piper),
   and macOS / Linux support.

## Ground rules

- Be kind. Many people who use this have a disability; keep that in mind in code,
  docs, and discussion.
- Keep it simple. Prefer the smallest change that works, and plain-language docs.
- Privacy first. Don't add anything that sends text, audio, or usage data anywhere
  without making it clear in the README and easy to turn off.
- Test on a real Windows machine with Claude Code before opening a pull request.

## License

By contributing, you agree that your contributions are licensed under the MIT License
that covers this project.
