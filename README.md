
# WhisperHub

A tabbed private-message (whisper) window for **World of Warcraft 1.12.1 / Turtle WoW**, built as a replacement for WIM.

All conversations live in **one window** with a contact list on the left, so there is no pile of floating windows to drag around. Your chat history is saved between sessions, either in a real SQLite database (via [HearthDB](https://github.com/copypasteonly/HearthDB)) or, if HearthDB is not installed, in the addon's saved variables.

> **Status:** early version (0.2.x). It is under active development, so expect rough edges. Bug reports with the exact error text are very welcome.

---

## Features

- **One window, tabbed conversations.** A contact list on the left shows every person you've whispered, coloured by class, with an unread counter. Click to switch, right-click to close a tab.
- **Persistent history with dates.** Messages are stored with a timestamp. Today's messages show `HH:MM`, older ones `DD.MM HH:MM`, and a date separator is drawn between days.
- **Who you're talking to.** The header shows level, race, class, guild and current zone. Data comes from units around you (target, party, raid) and from a throttled background `/who`.
- **Action buttons** on the right, like WIM's shortcut bar: Invite to group, Target, Add friend, Ignore / Unignore, Guild invite, Refresh info, Pin, Close tab, Delete history.
- **Pinned tabs** stay at the top of the list (marked with `*`).
- **Message icon + floating button.** A pulsing envelope icon pops up when a whisper arrives, and an optional always-visible round button shows the unread count. Both can be dragged **anywhere** on the screen; the button is *not* attached to the minimap.
- **Quick settings panel** (gear icon in the window, or right-click the floating button).
- **Combat friendly.** Optionally open the window only after combat ends, or hide it during combat.
- **Search your history** from chat: `/wh find <text>`.
- **Works with pfUI.** If pfUI is loaded, the window is skinned to match.
- Clickable item links in messages, and shift-clicking an item inserts its link into the WhisperHub edit box.

---

## Requirements

| | |
|---|---|
| **Required** | WoW client 1.12.1 (Turtle WoW) |
| **Recommended** | [HearthDB](https://github.com/copypasteonly/HearthDB) for unlimited SQLite history. Follow the installation instructions in its own repository. |
| **Optional** | pfUI (for skinning) |
| **Not required** | SuperWoW, nampower, ClassicAPI (the addon doesn't use them) |

Without HearthDB the addon still works, but history is kept in `SavedVariables` instead: the last 200 messages per contact, written to disk only on logout or `/reload`. If the game crashes, messages since your last logout/reload can be lost. With HearthDB, writes happen immediately and asynchronously.

---

## Installation

1. Download and extract the archive.
2. Copy the **`WhisperHub`** folder into your game's addons directory so that this file exists:

   ```
   <WoW folder>\Interface\AddOns\WhisperHub\WhisperHub.toc
   ```

3. **Disable or remove WIM** (and other whisper-window addons). Two addons that both intercept whispers will conflict.
4. *(Recommended)* Install HearthDB following its README.
5. Start the game and make sure **WhisperHub** is ticked on the character-select **AddOns** screen.
6. Log in. Type `/wh debug` and check the first line: `backend=hdb` means SQLite history is active, `backend=sv` means the fallback is in use.

---

## Quick start

- Receive a whisper → the window opens (if not in combat) and the envelope icon pulses.
- Type `/w Name` (without text), press **Whisper** on a unit/friend menu, or press `R` → the conversation opens as a tab.
- Type in the box at the bottom and press **Enter** to send. **Tab** jumps to the next conversation with unread messages. **Esc** leaves the edit box, **Esc** again closes the window.
- Scroll the message area with the mouse wheel (hold **Shift** to jump to the top/bottom).
- **Left-drag** the window, the floating button or the popup icon to move them.

---

## Slash commands

Use `/wh` or `/whisperhub`.

| Command | Description |
|---|---|
| `/wh` | Open or close the window |
| `/wh options` | Open the quick settings panel |
| `/wh resetpos` | Move the window, icon and button back to the centre of the screen |
| `/wh button on\|off` | Show or hide the floating button |
| `/wh icon on\|off\|always` | Popup icon: only when unread (default), never, or always visible |
| `/wh suppress on\|off` | Hide whispers from the normal chat frames |
| `/wh sound on\|off` | Sound on incoming whisper |
| `/wh autoopen on\|off` | Open the window automatically on an incoming whisper |
| `/wh deferopen on\|off` | If a whisper arrives in combat, open the window when combat ends |
| `/wh hidecombat on\|off` | Hide the window while in combat |
| `/wh takeover on\|off` | Intercept `/w`, `/r` and the "Whisper" buttons |
| `/wh who on\|off` | Background `/who` lookups for guild and zone |
| `/wh whodelay <seconds>` | Minimum delay between background `/who` requests (default 6, minimum 2) |
| `/wh keep <days>` | Delete history older than N days at login (`0` = keep forever, the default) |
| `/wh find <text>` | Search saved history; prints the 15 newest matches to chat |
| `/wh debug` | Print backend, counters and status, useful for bug reports |

---

## How it works

**Capture first, display second.** WhisperHub listens to the whisper chat events itself. Every message is first written into an in-memory model, and then queued for storage. The window is only a *view* of that model. A UI problem can therefore never lose a message. If the capture code ever throws an error, WhisperHub gives whispers back to the normal chat frames so nothing is lost silently.

**One window instead of many.** There is a single message frame, which is re-rendered (at most 200 lines) when you switch tabs. No per-window update loops are running, so dragging stays smooth no matter how many conversations you have.

**Storage.**
- With HearthDB, each message is inserted into a SQLite table through an asynchronous call, so the game doesn't stall. When you open a conversation, its latest messages (100 by default) are loaded from the database.
- Without HearthDB, the last 200 lines per contact are kept in `SavedVariables` (`WhisperHubDB`).
- Your own messages are recorded when the server confirms them, so failed sends are never shown as delivered.

**Normal chat.** By default, whispers are hidden from the standard chat frames because they live in WhisperHub. If you want them in both places, use `/wh suppress off`. The `/r` reply target is still tracked correctly.

**Player info.** Class, level, race and guild come for free from units you can see. The zone comes from a background `/who` query, which is queued and throttled and only runs for the conversation you're looking at (and only if its data is missing or older than two minutes). The result is intercepted so the stock Who panel never pops up. If the player is offline, the header says so.

**Opening conversations.** WhisperHub hooks `/w Name`, `/r`, the unit-menu "Whisper" entry and the friends-list "Send Message" button. If something doesn't open a tab, use `/wh takeover off` to get the default behaviour back.

---

## Troubleshooting

**`/wh` says "UI not ready".** The message includes the error text, so report it exactly. Also check that no other addon is breaking the load, and that you disabled WIM.

**A button prints "action failed: …".** The error means some API function is missing or behaves differently on your client. Please report the full text.

**History isn't saved between sessions.** Run `/wh debug`. If it says `backend=sv`, HearthDB isn't loaded and the fallback only saves on logout or `/reload`.

**Whispers appear twice (window + chat).** Another addon (WIM, pfUI chat tweaks) may be showing them too. Disable WIM first; `/wh suppress on` hides them from the default chat frames.

**The floating button disappeared.** Run `/wh resetpos`, and make sure `/wh button on` is set.

**Class colours look wrong on a non-English client.** Class names are matched by a built-in table plus whatever the addon learns from nearby players, so some localized names may be missing until you have seen that class in your group or target. Please report which ones.

---

## Data and uninstall

- Settings, pinned tabs, window positions and the cached player info are saved in `WhisperHubDB` (`WTF\Account\<account>\SavedVariables\WhisperHub.lua`).
- Message history is stored by HearthDB (see its documentation for the database location), or in the same SavedVariables file if you use the fallback.
- To uninstall, delete the `WhisperHub` folder. To wipe saved data as well, remove its SavedVariables file and the HearthDB database.
- Per-conversation deletion is available through the **Delete** button in the window.

---

## Credits

- Inspired by [WIM](https://github.com/refaim/WIM) (refaim's 1.12 port) for the window concept and shortcut bar.
- Inspired by [MessageBox](https://github.com/tilare/MessageBox) for the contact list and the message popup icon.
- [HearthDB](https://github.com/copypasteonly/HearthDB) provides the SQLite storage.
