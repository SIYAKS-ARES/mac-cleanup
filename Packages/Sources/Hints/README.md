# Hints

WhatsApp **layout** signature from `lstat` only.

A folder matches when `ChatStorage.sqlite` is a regular file and `Message/Media` is a directory. Selecting only `Message/Media` does not match.

The live Group Container (`~/Library/Group Containers/group.net.whatsapp.WhatsApp.shared`) is detected by path or directory inode. A copied folder is a different inode. Scan stays available; ChatStorage is still not opened unless the user Keeps sqlite (default Skip).

Captions are this scan, not a prior measurement. Those databases are never `open`ed by this package.
