# INSTALL Telegram Bot : 

```
wget https://raw.githubusercontent.com/Mehdi8932/telehram-downloader-bot/main/install_telegram_downloader.sh && chmod +x install_telegram_downloader.sh && sh install_telegram_downloader.sh
```
Done !
🧭 مراحل استفاده (خیلی مهم)
1️⃣ نصب
chmod +x install_telegram_downloader.sh
sudo ./install_telegram_downloader.sh

2️⃣ لاگین دستی (اجباری – فقط یک بار)
source /opt/telegram/venv/bin/activate
python /opt/telegram/telegram_video_downloader.py

3️⃣ اجرای دائمی
sudo systemctl start telegram-downloader
systemctl status telegram-downloader
