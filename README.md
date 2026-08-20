# log2tg

Monitor log file(s) and forward new lines to a Telegram chat via a bot,
running as a systemd service.

## Requirements

- `python3` (a `python` that resolves to Python 3 also works)
- Python's `venv` module
- `curl` or `wget`
- `systemd` (user session or root)

Everything else (the venv, `requests`) is set up automatically on first run.

## Install

```
curl -fsSL https://raw.githubusercontent.com/zharfanug/log2tg/latest/install.sh | sh
```

Installs `log2tg.sh` to `/usr/local/bin/log2tg` (via `sudo`) and marks it
executable, so it can be run as `log2tg` from anywhere. Downloads
`log2tg.sh` from GitHub unless a local `./log2tg.sh` is already present in
the current directory. Requires `sudo`, and `curl` or `wget`.

## Usage

```
log2tg.sh -l
log2tg.sh -a <name> -f <log file/glob> -k <api key> -c <chat id> [-b <interval>] [-ts <format>] [-ge <pattern>] [-pre <string>] [-y]
log2tg.sh -rm <name> [-y]
log2tg.sh -x -f <log file/glob> -k <api key> -c <chat id> [-b <interval>] [-ts <format>] [-ge <pattern>] [-pre <string>]
```

| Flag | Meaning |
|---|---|
| `-l` | List configured monitors |
| `-a <name>` | Add or update a monitor named `<name>` |
| `-rm <name>` | Remove a monitor named `<name>` |
| `-x` | Run in the foreground without creating a service (for testing) |
| `-f <file>` | Log file path or glob (`*.log`, `/home/*/mylog.log`) |
| `-k <key>` | Telegram bot API key |
| `-c <id>` | Telegram chat id |
| `-b <interval>` | Batch new lines and send every `<interval>`: `5`, `5s`, `5m`, `5h`. Default: no batching, sent as soon as seen |
| `-ts <format>` | Prefix each message with a timestamp in this `strftime` format, e.g. `"%Y-%m-%d %H:%M:%S"`. Default: no timestamp |
| `-ge <pattern>` | Exclude log lines matching this Python `re` pattern — they're dropped and never forwarded. Default: no exclusion |
| `-pre <string>` | Prefix every message with this fixed string. Default: no prefix |
| `-y` | Auto-confirm prompts (overwrite on `-a`, removal on `-rm`) |

Each forwarded line is formatted as `<pre><ts>: <line>` — `<pre>` and `<ts>`
are concatenated directly with no separator between them, and the `": "` is
only added if `-pre` or `-ts` was set. With neither set, the message is just
the raw line.

### Examples

Test against a file before turning it into a service:
```
./log2tg.sh -x -f /var/log/app.log -k <TOKEN> -c <CHAT_ID> -b 5s -ts "%Y-%m-%d %H:%M:%S"
```

Exclude noisy `DEBUG` lines and tag messages with a fixed prefix:
```
./log2tg.sh -x -f /var/log/app.log -k <TOKEN> -c <CHAT_ID> -ge "DEBUG" -pre "[app]"
```

Add a persistent monitor (creates and starts a systemd service):
```
./log2tg.sh -a app -f /var/log/app.log -k <TOKEN> -c <CHAT_ID> -b 5s
```

List configured monitors and their status:
```
./log2tg.sh -l
```

Remove one:
```
./log2tg.sh -rm app
```

## How it works

- Running as **root** manages `log2tg@<name>` as a system-scope systemd
  service (`/etc/systemd/system/`); running as a **regular user** manages it
  as a `--user` service (`~/.config/systemd/user/`).
- `-a` writes `~/.log2tg/<name>.conf` and starts `log2tg@<name>.service`,
  which runs `log2tg.py` inside a dedicated venv at `~/.log2tg`.
- `log2tg.py` only forwards lines appended **after** it starts (tail -f
  semantics) — it does not send a file's existing content.
- `-f` can be a glob; new files matching the pattern are picked up
  automatically. Lines from all matched files are forwarded as-is, without
  indicating which file they came from.
- Messages over Telegram's 4096-character limit are split into multiple
  sends.
- Link previews are always disabled — if a log line contains a URL,
  Telegram won't fetch and attach a preview card for it.
- Log rotation/truncation isn't specially handled in this version.

## Getting a bot token and chat id

1. Create a bot with [@BotFather](https://t.me/BotFather) on Telegram — it
   gives you a token like `123456789:AAExample-Token`.
2. Add the bot as an **admin** of the channel/group you want to post to.
3. Post any message in that channel.
4. Fetch the chat id:
   ```
   curl -s "https://api.telegram.org/bot<TOKEN>/getUpdates"
   ```
   Look for `"chat":{"id": ...}` in the response — that's your `<CHAT_ID>`
   (channels/groups have negative ids, e.g. `-1004442946624`).