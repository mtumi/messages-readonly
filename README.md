# messages-readonly

Lets Claude read your iMessage and SMS history on a Mac, without giving Claude Full Disk Access and without giving this setup any way to send a text.

**[Read the full guide](https://mtumi.github.io/messages-readonly/)**: how it works, why it exists, installing, using it, security, troubleshooting and uninstalling. The same guide is in this repository at [`docs/index.html`](docs/index.html).

## In short

- A tiny app, built on your Mac by the installer, is the only program with Full Disk Access. Once an hour it copies your Messages and Contacts databases read-only.
- A read-only connector lets Claude Desktop and Claude Code read that copy. It has no send tool, and nothing in it uses the network.
- One step is yours: macOS only lets a person grant Full Disk Access, so you turn on one switch in System Settings. The installer pops up a box with step-by-step instructions for it, opens the right windows, and waits for you.

## Questions

**Does it copy my photos, videos and attachments?** No, text only. Media lives in a separate Attachments folder that the app never opens, and the copy keeps only message text, times, senders and conversation names. On one Mac, a 447 MB Messages database became an 84 MB copy, contacts included. Each hourly run replaces the copy, so it doesn't pile up.

## Quick install

```
git clone https://github.com/mtumi/messages-readonly ~/messages-readonly
cd ~/messages-readonly
./install.sh
```

Or paste the install prompt from the guide into Claude Code and let it walk you through.

## License and disclaimer

MIT; see [LICENSE](LICENSE). A personal project shared as is, not affiliated with Apple or Anthropic. It gives an AI assistant access to private conversations, including other people's messages to you; you are responsible for how you use it. Read the guide's disclaimer before installing.

Made by Michael Tuminello. If something doesn't work, open an issue on this repository.
