# Working with archives

[Back to Twister](../../README.md)

## Extract or convert an archive

Twister exposes ZIP, TAR, GZIP and RAR inputs for extraction, with ZIP, TAR and GZIP as archive conversion targets. RAR creation is not offered. Choose **Extract Archive** when you need the contents rather than another archive format.

## Understand GZIP output

A GZIP input can contain a compressed TAR archive or one ordinary file. Archive conversion to GZIP writes a TAR stream with GZIP compression, allowing it to hold several entries. Use ZIP when you need a familiar multi-file archive without the TAR layer.

## Allow for extraction limits

Extraction stops after 100,000 entries or more than 20 GiB of expanded file data. The compressed download size can be much smaller than the expanded data. An archive that exceeds a limit is rejected rather than partially published as a successful extraction.

## Handle a rejected archive

Twister rejects paths outside its extraction area, unsafe links, duplicate file paths and unsupported special files. A rejection can therefore indicate an unsafe or ambiguous archive even when its extension looks correct. Use a trusted source to obtain a fresh archive instead of assuming renaming the file will repair it.
