# Build and release

## Toolchain

The project pins Flutter and Dart compatibility in `pubspec.yaml` and `pubspec.lock`. Android release builds use JDK 17. iOS signing builds require macOS, Xcode, an Apple team, a certificate, and a matching provisioning profile.

Install dependencies with:

```sh
flutter pub get --enforce-lockfile
```

## Android

Unsigned local builds:

```sh
flutter build apk --release
flutter build appbundle --release
```

For a signed build, create `android/key.properties` with a keystore path, store password, key password, and alias. Keep the keystore and passwords outside Git. Reuse the same signing identity for upgrades.

The APK is directly installable. The AAB is intended for Google Play or another store and is not a direct-install package.

## iOS

Open the `ios/` project in Xcode, select the correct team and bundle identifier, configure signing, and archive the Runner target. Export an IPA using the distribution method required by the provisioning profile.

## GitHub Actions

- `Mobile CI` runs on repository changes and provides the general build/automation pipeline.
- `Signed packages` is manually dispatched for signed Android, iOS, or both.
- `Branch releases` builds preview packages for non-default branches and uploads APK/AAB/IPA files directly to a GitHub Release.
- `Studio contract` is a manually callable integration workflow for a compatible Studio checkout.

Release assets are separate GitHub Release files. Actions artifacts are temporary workflow outputs and are not the distribution channel for branch releases.

## Secrets and variables

Release workflows may require Android signing secrets, iOS certificate/profile secrets, an Apple team ID, and the `release` environment. Configure these in GitHub Actions environments rather than committing them to the repository.

Never commit:

```text
android/key.properties
.local/signing/
*.jks
*.keystore
*.p12
*.mobileprovision
```
