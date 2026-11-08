# messages-readonly

Lets Claude read your iMessage and SMS history on a Mac through a read-only MCP server, without giving Claude Full Disk Access and without giving this setup any way to send a text.

**[Read the full guide](https://mtumi.github.io/messages-readonly/)**: how it works, why it exists, installing, using it, security, troubleshooting and uninstalling. The same guide is in this repository at [`docs/index.html`](docs/index.html).

## In short

- A tiny app, built on your Mac by the installer, is the only program with Full Disk Access. Once an hour it copies your Messages and Contacts databases read-only.
- A read-only connector lets Claude Desktop and Claude Code read that copy. It is a local Model Context Protocol (MCP) server that talks to Claude over standard input and output, written from the protocol specification in about 330 lines of Python's standard library, with no SDK and no third-party packages. It has no send tool, and nothing in it uses the network.
- One step is yours: macOS only lets a person grant Full Disk Access, so you turn on one switch in System Settings. The installer pops up a box with step-by-step instructions for it, opens the right windows, and waits for you.

## Questions

**Does it copy my photos, videos and attachments?** No, text only. Media lives in a separate Attachments folder that the app never opens, and the copy keeps message text, times, senders, conversation names and attachment file names, never the files themselves. On one Mac, a 447 MB Messages database became an 84 MB copy, contacts included. Each hourly run replaces the copy, so it doesn't pile up.

## Install

You need a Mac, Claude Desktop or Claude Code, and Apple's Command Line Tools (macOS offers to install them the first time). The easiest way is to let Claude Code install it: copy the [install prompt from the guide](https://mtumi.github.io/messages-readonly/#install), which has Claude read and explain the code to you before running anything, then walks you through the rest. The guide also has the full steps for installing by hand.

One step is always yours: macOS only lets a person turn on Full Disk Access, so a box on screen walks you through it in System Settings.

So far it has been tested on one Mac, running macOS 15. If something goes wrong, the guide's [troubleshooting section](https://mtumi.github.io/messages-readonly/#trouble) covers the common problems.

## License and disclaimer

MIT; see [LICENSE](LICENSE). A personal project shared as is, not affiliated with Apple or Anthropic. It gives an AI assistant access to private conversations, including other people's messages to you; you are responsible for how you use it. Read the guide's disclaimer before installing.

Made by Michael Tuminello. If something doesn't work, open an issue on this repository.
