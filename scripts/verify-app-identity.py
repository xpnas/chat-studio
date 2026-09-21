#!/usr/bin/env python3
"""Fail CI on client identity drift; upstream wire values remain unchanged."""
from pathlib import Path
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
APP_ID = "ai.chatstudio.app"
CHANNEL = APP_ID + "/file_export"
SOURCE_ROOTS = {"lib", "test", "integration_test", "test_driver", "android", "ios", "scripts", "tools", ".github"}
# These are real external protocol / repository values, never our app identity.
PROTOCOL_VALUES = (
    "ekko-agent.png",
    "ekko-agent",
    "ekko_agent",
    "ekko",
    "Ekko",
)
# Exact upstream Agent adapter identifiers; do not permit arbitrary prefixes.
AGENT_MANAGEMENT_IDENTIFIERS = (
    "ekkoSkills", "ekkoSkill", "createEkkoSkill", "setEkkoSkillEnabled",
    "updateEkkoSkill", "deleteEkkoSkill", "ekkoMcpServers", "addEkkoMcp",
    "updateEkkoMcp", "deleteEkkoMcp", "testEkkoMcp", "ekkoMemory",
    "updateEkkoMemory", "deleteEkkoMemory", "_deleteEkkoSkill",
    "_editEkkoMemory", "_showEkkoSkillEditor",
)
EXTERNAL_FILES = {
    "lib/data/studio_protocol.dart": PROTOCOL_VALUES,
    "lib/data/agent_capabilities.dart": PROTOCOL_VALUES + AGENT_MANAGEMENT_IDENTIFIERS,
    "lib/ui/agent_capabilities_screen.dart": PROTOCOL_VALUES + AGENT_MANAGEMENT_IDENTIFIERS,
    # These UI strings describe upstream wire/runtime names; they are not the
    # Chat Studio client identity and must remain visible to users.
    "lib/l10n_catalog.dart": PROTOCOL_VALUES,
    "lib/ui/management_screen.dart": PROTOCOL_VALUES,
    "lib/data/agent_settings.dart": PROTOCOL_VALUES,
    "lib/ui/agent_configuration_screen.dart": PROTOCOL_VALUES,
    "lib/ui/widgets/settings_editors.dart": PROTOCOL_VALUES,
    ".github/workflows/studio-contract.yml": ("EKKOLearnAI/hermes-studio",),
}
errors = []


def check(ok, message):
    if not ok:
        errors.append(message)


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def verify():
    check(re.search(r"^name: chatstudio$", read("pubspec.yaml"), re.M), "Dart package must be chatstudio")
    gradle = read("android/app/build.gradle.kts")
    for field in ("namespace", "applicationId"):
        check(re.search(rf'{field}\s*=\s*"{re.escape(APP_ID)}"', gradle), f"Android {field} mismatch")
    kotlin = "android/app/src/main/kotlin/ai/chatstudio/app/MainActivity.kt"
    check(re.search(rf"^package {re.escape(APP_ID)}$", read(kotlin), re.M), "Kotlin package/path mismatch")
    for path in (kotlin, "ios/Runner/AppDelegate.swift", "lib/data/file_export.dart"):
        check(CHANNEL in read(path), f"File export channel mismatch: {path}")
    bundle_ids = re.findall(r"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);", read("ios/Runner.xcodeproj/project.pbxproj"))
    check(sorted(bundle_ids) == sorted([APP_ID] * 3 + [APP_ID + ".RunnerTests"] * 3), "iOS bundle IDs/configurations mismatch")
    with (ROOT / "ios/Runner/Info.plist").open("rb") as source:
        plist = plistlib.load(source)
    check(plist.get("CFBundleName") == "chatstudio", "iOS bundle name mismatch")
    check(plist.get("CFBundleDisplayName") == "Chat Studio", "iOS display name mismatch")
    check('android:label="Chat Studio"' in read("android/app/src/main/AndroidManifest.xml"), "Android display name mismatch")
    check('title: \'Chat Studio\'' in read("lib/main.dart"), "Flutter display name mismatch")
    storage = read("lib/data/app_storage.dart")
    # Web login no longer registers or persists an app-login device identity.
    for key in ("session", "servers", "choice"):
        check(f"chatstudio.{key}.v1" in storage, f"Storage namespace mismatch: {key}")
    files = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT).decode("utf-8").split("\0")
    for name in sorted(set(files)):
        if not name or not (ROOT / name).is_file():
            continue
        if name.split("/")[0] not in SOURCE_ROOTS and name not in ("pubspec.yaml", "pubspec.lock"):
            continue
        check(not re.search("ekko", name, re.I), f"Legacy client path: {name}")
        if name == "scripts/verify-app-identity.py":
            continue  # The guard necessarily names the forbidden strings.
        try:
            content = read(name)
        except UnicodeError:
            continue  # Native icon/image assets.
        allowed = EXTERNAL_FILES.get(name, ())
        if name.startswith(("test/", "integration_test/")):
            allowed = PROTOCOL_VALUES  # Keep literal wire assertions independent.
        for value in allowed:
            # Match complete identifiers / literals only, not arbitrary prefixes.
            content = re.sub(r"(?<![\w-])" + re.escape(value) + r"(?![\w-])", "", content)
        for i, line in enumerate(content.splitlines(), 1):
            if re.search("ekko", line, re.I):
                errors.append(f"Legacy client identifier: {name}:{i}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Chat Studio identity verified: chatstudio / {APP_ID}; upstream compatibility preserved.")
    return 0


if __name__ == "__main__":
    sys.exit(verify())
