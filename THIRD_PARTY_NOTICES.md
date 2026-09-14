# Third-party notices

This mobile client was independently implemented against the protocol of EKKOLearnAI/hermes-studio, tag v1.0.3, commit b44c74318fe5a0a1f3aed29d5095393964fc3d62. The upstream source remains in a separate checkout and is not vendored into this repository. Its root LICENSE identifies Business Source License 1.1; review that license and its additional terms before redistributing or operating derivatives. No claim is made that the upstream is MIT-licensed.

The mobile project uses Flutter and the packages pinned in pubspec.lock, notably http, socket_io_client, flutter_secure_storage, shared_preferences, uuid, flutter_markdown_plus, url_launcher, record, path_provider, file_picker, image_picker, and mime. Each retains its own license. Flutter bundles package license information for runtime license displays; inspect the resolved packages' LICENSE files for exact terms.

The Ekko mark in this repository is code-drawn, not copied from the upstream logo. scripts/generate-icons.ps1 regenerates the raster assets. UI previews use a locally supplied font solely for rendering and do not redistribute that font file. The mobile application itself does not bundle that preview font.

No new open-source license is imposed on the repository owner's original application code by this notice. Choose an appropriate project license before public redistribution. The UI is inspired by familiar conversational app patterns, but does not copy ChatGPT trademarks or claim affiliation with OpenAI.
