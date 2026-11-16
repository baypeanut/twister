# Optional tools

[Back to Twister](../../README.md)

## Install only what you need

Setup separates optional tools into three groups. Media checks FFmpeg and FFprobe, Office checks LibreOffice, and Web download tools checks yt-dlp and Deno. You can return to the workspace without installing any group and add missing tools when a conversion needs them. Converting media needs the Media group only.

## Web downloads are opt-in

**Download a link** stays in the workspace, but the Web download tools are not installed with the others. Until they are present, the download window explains what is missing and offers **Install web download tools**; a link you already pasted is kept and checked when the tools are ready. Settings → General → Optional extras has a **Web downloads** switch: it is on when the tools are installed, and turning it off closes the feature without deleting anything.

## Remove a tool group

Each group that setup downloaded shows its version, its folder and its size with a **Remove** button. Removing a group deletes only the copy Twister downloaded for it. A tool from Homebrew, from inside the app or from a `TWISTER_` override stays where it is and keeps being used.

## Reuse an installed tool

Twister checks supported existing tool locations before asking for an installation. A tool must resolve to a nonempty executable file, not just a directory with the same name. Standard locations include Homebrew paths and the normal LibreOffice application location.

## Know what setup downloads

Optional tool packages come from pinned HTTPS sources and are checked against SHA-256 values. Downloads are prepared in staging before a complete installation is published. Installed tool storage is `~/Library/Application Support/Twister/Tools`; setup needs a network connection, while completed local conversions use the installed tools.

## Cancel or retry setup

Cancel stops the current setup work and keeps tools that were already usable. If one tool group completed before another failed, its installation remains available. Return to setup to retry the missing group; an interrupted download does not require deleting a working installation.

## Use an explicit executable

For development or troubleshooting, set the relevant environment variable before launching the CLI or app from that environment. Supported overrides include `TWISTER_FFMPEG`, `TWISTER_FFPROBE`, `TWISTER_EXIFTOOL` and `TWISTER_SOFFICE`. Setup never removes a file an override points at. Point each value at the executable file, and check CLI resolution with `twister-cli dependencies` once the conversion dependencies are available.
