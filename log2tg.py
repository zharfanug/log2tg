#!/usr/bin/env python3
import glob
import os
import re
import sys
import time
from datetime import datetime

import requests

POLL_INTERVAL = 1
TELEGRAM_MAX_LEN = 4096

LOG_FILE = os.environ.get("LOG_FILE")
API_KEY = os.environ.get("API_KEY")
CHAT_ID = os.environ.get("CHAT_ID")
BATCH_INTERVAL = int(os.environ.get("BATCH_INTERVAL") or 0)
TS_FORMAT = os.environ.get("TS_FORMAT") or ""
GREP_EXCLUDE = os.environ.get("GREP_EXCLUDE") or ""
PREFIX = os.environ.get("PREFIX") or ""

if not LOG_FILE or not API_KEY or not CHAT_ID:
  print("ERROR: LOG_FILE, API_KEY and CHAT_ID must be set", file=sys.stderr)
  sys.exit(1)

EXCLUDE_RE = re.compile(GREP_EXCLUDE) if GREP_EXCLUDE else None


def log(msg):
  print(f"{datetime.now().isoformat()} - {msg}", flush=True)


def send_telegram(text):
  url = f"https://api.telegram.org/bot{API_KEY}/sendMessage"
  for i in range(0, len(text), TELEGRAM_MAX_LEN):
    chunk = text[i:i + TELEGRAM_MAX_LEN]
    try:
      resp = requests.post(
        url,
        data={"chat_id": CHAT_ID, "text": chunk, "disable_web_page_preview": True},
        timeout=10,
      )
      if not resp.ok:
        log(f"ERROR sending to telegram: {resp.status_code} {resp.text}")
    except requests.RequestException as exc:
      log(f"ERROR sending to telegram: {exc}")


def format_line(raw_line):
  line = raw_line.decode("utf-8", errors="replace").rstrip("\n")
  if EXCLUDE_RE and EXCLUDE_RE.search(line):
    return None
  header = f"{PREFIX}{datetime.now().strftime(TS_FORMAT)}"
  if header:
    return f"{header}: {line}"
  return line


def poll_new_lines(handles):
  lines = []
  for path in list(handles.keys()):
    fh = handles[path]
    try:
      while True:
        pos = fh.tell()
        raw = fh.readline()
        if not raw.endswith(b"\n"):
          # incomplete line — rewind and wait for the rest to be written
          fh.seek(pos)
          break
        formatted = format_line(raw)
        if formatted is not None:
          lines.append(formatted)
    except OSError as exc:
      log(f"ERROR reading {path}: {exc}")
      fh.close()
      del handles[path]
  return lines


def watch_new_files(handles):
  for path in glob.glob(LOG_FILE):
    if path in handles:
      continue
    try:
      fh = open(path, "rb")
      fh.seek(0, os.SEEK_END)
      handles[path] = fh
      log(f"watching {path}")
    except OSError as exc:
      log(f"ERROR opening {path}: {exc}")


def main():
  handles = {}
  buffer = []
  last_flush = time.time()

  while True:
    watch_new_files(handles)
    buffer.extend(poll_new_lines(handles))

    now = time.time()
    should_flush = buffer and (BATCH_INTERVAL <= 0 or now - last_flush >= BATCH_INTERVAL)
    if should_flush:
      send_telegram("\n".join(buffer))
      buffer = []
      last_flush = now

    time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
  main()
