# Troubleshooting

[Back to Twister](../../README.md)

## Begin with the reported error

Check the selected source files, requested action and exact error text first. A format or tool can depend on the whole selection, and an input may have moved since it was selected. Try one available source file with a supported action before changing several settings at once.

## Some files of a batch failed

Open the file list of the batch in the workspace to read the reason beside each failed file. The files that succeeded are already saved and recorded in Library. Fix or replace the failed sources, then use **Retry failed**; it does not export the finished files again. From the command line, failed files are reported on standard error and the exit status is 3 when only some of them failed.

## An export folder is unavailable

Reopen the output-folder chooser and select an existing writable folder, or restore **Beside originals**. Re-selecting a folder renews a stale saved access grant. Changing the preference affects future jobs, so let an active job finish or cancel it before starting a replacement export.

## Presets are missing

Presets are kept in `~/Library/Application Support/Twister/Presets.json`. When that file cannot be read as a presets file, Twister moves it aside as `Presets.corrupt-DATE.json` in the same folder, starts with an empty list and says so in the Presets list. Repair the copy and bring its presets back with `twister-cli preset import`. A preset saved by a newer Twister that this version cannot read is not shown, and it stays in the file.

## Services are missing in Finder

Open Twister once, then look under **Services** in Finder's context menu for a selected file. Enable the entries in System Settings → Keyboard → Keyboard Shortcuts → Services → Files and Folders if they are turned off. **Run Twister Preset…** reports that no preset fits when none of the saved presets supports every selected file.

## A media link will not download

Check the network connection and whether Media setup is complete. A supported provider may still reject a link because content is unavailable or access is restricted. Keep the error text when reporting a failure, but remove private links, cookies, credentials and personal file paths from a public report.

## Updates are not connected

Automatic updates are disabled in the default local build. A release feed and update-signing key must be configured before update checks are available. Reinstalling optional media or Office tools does not configure an application update channel; see the [dependency guide](../dependencies.md) for the distribution status.
