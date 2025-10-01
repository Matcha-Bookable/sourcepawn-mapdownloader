# Map Downloader (SourcePawn)
A fork of [spiretf/mapdownloader](https://github.com/spiretf/mapdownloader), but implemented with md5sum checking, updated syntax and uses [neocurl (2.0.0)](https://github.com/sapphonie/SM-neocurl-ext/releases/tag/v2.0.0-beta).

I made this because the bookable we use constantly pulls map from our server which sometimes results in corrupted file and causes lingering instance.

> This will not work for normal fastdl servers, unless the fastdl server also includes a *.md5sum file for the plugin for checking.