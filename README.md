# Map Downloader (SourcePawn)
A fork of [spiretf/mapdownloader](https://github.com/spiretf/mapdownloader), but implemented with md5sum checking and updated syntax.

I made this because the bookable we use constantly pulls map from our server which sometimes results in corrupted file and causes lingering instance.

> This will not work for normal fastdl servers, unless the fastdl server also includes a *.md5sum file for the plugin for checking.