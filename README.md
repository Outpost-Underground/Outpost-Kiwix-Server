# Outpost Kiwix USB Builder

A PowerShell script that turns a USB drive (thumbdrive or USB hard drive) into a portable offline Kiwix server.

The script:

- Detects USB drives safely (no formatting, no wiping)
- Downloads official Kiwix tools for Windows
- Creates an `Outpost-Kiwix-Server` folder on the USB drive
- Sets up a simple batch menu so non-technical users can:
  - Start/stop the Kiwix server
  - Open the ZIMs folder
  - Rebuild the Kiwix library
  - Download an optional curated “prepper” ZIM pack
  - See connection instructions for other devices on the LAN

Once built, you can plug the USB into almost any Windows PC and serve offline content over the local network.

Note: User must either download the starter "prepper" ZIM pack, or copy ZIM files into the ZIM folder in order for the server to make content available. Fun fact: the "prepper" ZIM pack includes WikiHow 🛠

Additional ZIM files can be dowloaded from:
https://library.kiwix.org/
https://download.kiwix.org/

---

After running the script, your USB will contain:

```text
<USB-DRIVE>:\Outpost-Kiwix-Server\
    kiwix-tools-win\
    ZIMs\
    detect-ip.ps1
    OUTPOST-KIWIX-MENU.bat
    README-OUTPOST.txt
