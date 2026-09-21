# Server workspace and gestures

The workspace belongs to the Agent server, not to the phone's local filesystem.

## Chat gestures

- Swipe right in the conversation area to open the history drawer.
- Swipe left in the conversation area to open the server workspace.
- The composer and text-selection gestures are excluded from drawer navigation.
- The same navigation model is used by direct chats and group chats.

## Workspace behavior

The workspace screen displays the server-reported absolute path and its files. Folder selection sends the server path or `fullPath` back to the current conversation; the app never resolves a server path against the phone filesystem.

Users can browse folders, preview supported files, and select a working folder when the server permits it. A running task may lock workspace changes. Errors such as a missing server directory are shown inside the workspace screen and do not change the phone's local files.
