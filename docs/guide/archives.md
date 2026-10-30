# Working with archives

[Back to Twister](../../README.md)

## Extract or convert an archive

Twister exposes ZIP, TAR, GZIP and RAR inputs for extraction, with ZIP, TAR and GZIP as archive conversion targets. RAR creation is not offered. Choose **Extract Archive** when you need the contents rather than another archive format.

## Understand GZIP output

A GZIP input can contain a compressed TAR archive or one ordinary file. Archive conversion to GZIP writes a TAR stream with GZIP compression, allowing it to hold several entries. Use ZIP when you need a familiar multi-file archive without the TAR layer.
