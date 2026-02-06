#!/bin/bash
set -e

APP_DIR="/opt/telegram"
VENV_DIR="$APP_DIR/venv"
SCRIPT_NAME="telegram_video_downloader.py"
SERVICE_NAME="telegram-downloader"
SESSION_FILE="$APP_DIR/session.session"

echo "📦 Installing Telegram Video Downloader..."

# ---------- Packages ----------
apt update
apt install -y python3 python3-venv python3-pip sqlite3

# ---------- App dir ----------
mkdir -p $APP_DIR
mkdir -p /Downloads

# ---------- venv ----------
python3 -m venv $VENV_DIR
source $VENV_DIR/bin/activate

pip install --upgrade pip
pip install telethon

# ---------- User config ----------
read -p "API ID: " API_ID
read -p "API HASH: " API_HASH
read -p "Channel link (@username or invite link): " CHANNEL
read -p "Notify chat_id (PV): " NOTIFY_CHAT_ID

# ---------- Python script ----------
cat > $APP_DIR/$SCRIPT_NAME <<EOF
from telethon import TelegramClient, events
from telethon.network.connection.tcpabridged import ConnectionTcpAbridged
import os
import time
import sqlite3
import traceback
import asyncio

# ========= تنظیمات =========
API_ID = $API_ID
API_HASH = "$API_HASH"

CHANNEL = "$CHANNEL"
DOWNLOAD_PATH = "/Downloads"

NOTIFY_CHAT_ID = $NOTIFY_CHAT_ID
DB_PATH = "/Downloads/downloads.db"
# ===========================

os.makedirs(DOWNLOAD_PATH, exist_ok=True)

# ---------- SQLite ----------
conn = sqlite3.connect(DB_PATH, check_same_thread=False)
cursor = conn.cursor()

cursor.execute("""
CREATE TABLE IF NOT EXISTS downloads (
    message_id TEXT PRIMARY KEY,
    filename TEXT,
    status TEXT DEFAULT 'started',  -- started / finished
    downloaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
""")
conn.commit()
# ---------------------------

# ---------- Client ----------
client = TelegramClient(
    "session",
    API_ID,
    API_HASH,
    connection=ConnectionTcpAbridged,
    connection_retries=None,
    request_retries=None,
    flood_sleep_threshold=60
)
# ---------------------------

# ---------- Utils ----------
def format_size(b):
    return f"{b / (1024 * 1024):.2f} MB"

def format_time(sec):
    if sec <= 0 or sec == float("inf"):
        return "?"
    m, s = divmod(int(sec), 60)
    h, m = divmod(m, 60)
    return f"{h:02}:{m:02}:{s:02}"

def is_downloaded(msg_id):
    cursor.execute("SELECT 1 FROM downloads WHERE message_id=?", (msg_id,))
    return cursor.fetchone() is not None

def save_download(msg_id, filename):
    cursor.execute(
        "INSERT OR IGNORE INTO downloads (message_id, filename) VALUES (?, ?)",
        (msg_id, filename)
    )
    conn.commit()
# ---------------------------

# ---------- Handler ----------
@client.on(events.NewMessage(chats=CHANNEL))
async def handler(event):
    # فقط ویدیو
    if not (
        event.video or
        (event.document and event.document.mime_type and event.document.mime_type.startswith("video/"))
    ):
        return

    msg_id = str(event.message.id)
    filename = event.file.name or f"{msg_id}.mp4"
    filepath = os.path.join(DOWNLOAD_PATH, filename)

    # جلوگیری از دانلود تکراری
    if is_downloaded(msg_id):
        return

    start_time = time.time()
    last_update = 0
    progress_msg = None

    async def progress(current, total):
        nonlocal last_update
        now = time.time()
        if total and (now - last_update) >= 3:
            percent = int(current * 100 / total)
            speed = current / (now - start_time) if (now - start_time) > 0 else 0
            eta = (total - current) / speed if speed > 0 else 0
            if progress_msg:
                await progress_msg.edit(
                    f"📥 Downloading...\n"
                    f"📄 {filename}\n"
                    f"📊 Progress: {percent}%\n"
                    f"📦 {format_size(current)} / {format_size(total)}\n"
                    f"🚀 Speed: {format_size(speed)}/s\n"
                    f"⏱ ETA: {format_time(eta)}"
                )
            last_update = now

    try:
        # پیام زنده در PV (حرفه‌ای)
        progress_msg = await client.send_message(
            NOTIFY_CHAT_ID,
            f"📥 Download started\n📄 {filename}\n📊 Progress: 0%"
        )

        path = await event.download_media(
            file=filepath,
            progress_callback=progress
        )

        save_download(msg_id, filename)

        if progress_msg:
            await progress_msg.edit(
                f"✅ Download finished\n\n"
                f"📄 {filename}\n"
                f"📦 Size: {format_size(os.path.getsize(filepath))}\n"
                f"📁 Saved to: {DOWNLOAD_PATH}"
            )

    except Exception as e:
        if progress_msg:
            await progress_msg.edit(f"❌ Download failed\n\n{str(e)}")
        traceback.print_exc()
# ---------------------------

# ---------- Startup ----------
async def main():
    await client.start()
    await client.send_message(
        NOTIFY_CHAT_ID,
        f"🤖 Telegram video downloader started\n📁 Downloads path: {DOWNLOAD_PATH}"
    )
    print("Bot is running...")
    await client.run_until_disconnected()

asyncio.run(main())
EOF

# ---------- systemd ----------
cat > /etc/systemd/system/$SERVICE_NAME.service <<EOF
[Unit]
Description=Telegram Video Downloader
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR
ExecStart=$VENV_DIR/bin/python $APP_DIR/$SCRIPT_NAME
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# ---------- Enable ----------
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable $SERVICE_NAME

# ---------- Run interactive if session missing ----------

source /opt/telegram/venv/bin/activate
python /opt/telegram/telegram_video_downloader.py
