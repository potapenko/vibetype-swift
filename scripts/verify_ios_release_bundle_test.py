#!/usr/bin/env python3
"""Tests for verify_ios_release_bundle.py."""

from __future__ import annotations

import copy
import contextlib
import importlib.util
import io
import plistlib
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path
from unittest import mock


SCRIPT_PATH = Path(__file__).with_name("verify_ios_release_bundle.py")


def load_verifier_module():
    spec = importlib.util.spec_from_file_location("verify_ios_release_bundle", SCRIPT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load verify_ios_release_bundle.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["verify_ios_release_bundle"] = module
    spec.loader.exec_module(module)
    return module


class IOSReleaseBundleVerifierTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_verifier_module()
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.app = self.make_bundle(Path(self.temporary_directory.name))

    def make_bundle(self, root: Path) -> Path:
        app = root / "HoldType-iOS.app"
        keyboard = app / "PlugIns" / "HoldTypeKeyboard.appex"
        keyboard.mkdir(parents=True)

        self.write_plist(
            app / "Info.plist",
            {
                "CFBundleExecutable": "HoldType-iOS",
                "CFBundleIdentifier": "app.holdtype.HoldType.ios",
                "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": "1.0",
                "CFBundleVersion": "1",
                "NSMicrophoneUsageDescription": self.module.MICROPHONE_PURPOSE,
            },
        )
        self.write_plist(
            keyboard / "Info.plist",
            {
                "CFBundleExecutable": "HoldTypeKeyboard",
                "CFBundleIdentifier": "app.holdtype.HoldType.ios.keyboard",
                "CFBundlePackageType": "XPC!",
                "CFBundleShortVersionString": "1.0",
                "CFBundleVersion": "1",
                "NSExtension": {
                    "NSExtensionAttributes": {"RequestsOpenAccess": False},
                    "NSExtensionPointIdentifier": "com.apple.keyboard-service",
                    "NSExtensionPrincipalClass": (
                        "HoldTypeKeyboard.KeyboardViewController"
                    ),
                },
            },
        )
        self.write_plist(
            app / "PrivacyInfo.xcprivacy",
            copy.deepcopy(self.module.APP_PRIVACY_MANIFEST),
        )
        self.write_plist(
            keyboard / "PrivacyInfo.xcprivacy",
            copy.deepcopy(self.module.KEYBOARD_PRIVACY_MANIFEST),
        )
        (app / "Assets.car").write_bytes(b"compiled-assets")
        self.write_png(app / "AppIcon60x60@2x.png", 120, 120)
        self.write_png(
            app / "AppIcon76x76@2x~ipad.png",
            152,
            152,
        )
        self.write_mach_o(app / "HoldType-iOS")
        self.write_mach_o(keyboard / "HoldTypeKeyboard")
        return app

    @staticmethod
    def write_plist(path: Path, value: dict[str, object]) -> None:
        with path.open("wb") as handle:
            plistlib.dump(value, handle)

    @staticmethod
    def read_plist(path: Path) -> dict[str, object]:
        with path.open("rb") as handle:
            value = plistlib.load(handle)
        if not isinstance(value, dict):
            raise AssertionError("fixture plist is not a dictionary")
        return value

    @staticmethod
    def write_mach_o(path: Path, payload: bytes = b"") -> None:
        path.write_bytes(b"\xcf\xfa\xed\xfe" + b"fixture" + payload)
        path.chmod(0o755)

    @staticmethod
    def write_png(
        path: Path,
        width: int,
        height: int,
        *,
        color_type: int = 2,
    ) -> None:
        def chunk(kind: bytes, payload: bytes) -> bytes:
            checksum = zlib.crc32(kind + payload) & 0xFFFFFFFF
            return (
                struct.pack(">I", len(payload))
                + kind
                + payload
                + struct.pack(">I", checksum)
            )

        pixels = {
            2: b"\x00\x00\x00",
            6: b"\x00\x00\x00\x80",
        }
        pixel = pixels[color_type]
        ihdr = struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0)
        scanline = b"\x00" + (pixel * width)
        path.write_bytes(
            b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(scanline * height))
            + chunk(b"IEND", b"")
        )

    def runner(self, command, *, timeout=None):
        del timeout
        executable = Path(command[-1])
        tool = command[0]
        if tool == "otool":
            return self.module.ToolResult(
                0,
                stdout=(
                    f"{executable}:\n"
                    "\t/System/Library/Frameworks/Foundation.framework/Foundation "
                    "(compatibility version 300.0.0, current version 300.0.0)\n"
                    "\t/usr/lib/libSystem.B.dylib "
                    "(compatibility version 1.0.0, current version 1.0.0)\n"
                ),
            )
        if tool == "nm":
            return self.module.ToolResult(0, stdout="_NSExtensionMain\n")
        if tool == "strings":
            return self.module.ToolResult(0, stdout="HoldTypeKeyboard\n")
        if tool == "codesign" and "--entitlements" in command:
            return self.module.ToolResult(0)
        if tool == "codesign" and "-d" in command:
            identifier = (
                "app.holdtype.HoldType.ios.keyboard"
                if executable.name == "HoldTypeKeyboard"
                else "app.holdtype.HoldType.ios"
            )
            return self.module.ToolResult(
                0,
                stderr=(
                    f"Executable={executable}\n"
                    f"Identifier={identifier}\n"
                    "CodeDirectory v=20400 size=100 flags=0x2(adhoc)\n"
                    "CDHash=0123456789abcdef\n"
                ),
            )
        if tool == "codesign" and "--verify" in command:
            return self.module.ToolResult(0)
        return self.module.ToolResult(99, stderr=f"unexpected command: {command!r}")

    def checks_by_name(self, runner=None) -> dict[str, object]:
        checks = self.module.collect_checks(self.app, runner=runner or self.runner)
        return {check.name: check for check in checks}

    def test_accepts_complete_generic_simulator_release_bundle(self) -> None:
        checks = self.module.collect_checks(self.app, runner=self.runner)

        self.assertFalse([check for check in checks if check.status == "fail"])
        names = {check.name for check in checks}
        self.assertIn("app:privacy-manifest", names)
        self.assertIn("keyboard:privacy-manifest", names)
        self.assertIn("app:privacy-manifest:contract", names)
        self.assertIn("keyboard:privacy-manifest:contract", names)
        self.assertIn("app:assets-catalog", names)
        self.assertIn("app:icon:iphone", names)
        self.assertIn("app:icon:ipad", names)
        self.assertIn("app:internal-ui-markers", names)
        self.assertIn("keyboard:dependencies:system-only", names)
        self.assertIn("keyboard:signature:bundle-seal", names)
        self.assertIn("app:signature:bundle-seal", names)
        self.assertEqual(
            next(
                check
                for check in checks
                if check.name == "app:processed-entitlements"
            ).status,
            "manual",
        )

    def test_requires_app_extension_and_exact_executable_identity(self) -> None:
        missing_app = Path(self.temporary_directory.name) / "Missing.app"
        checks = self.module.collect_checks(missing_app, runner=self.runner)
        self.assertEqual(checks[0].name, "app")
        self.assertEqual(checks[0].status, "fail")

        keyboard = self.app / "PlugIns" / "HoldTypeKeyboard.appex"
        moved_keyboard = keyboard.with_suffix(".missing")
        keyboard.rename(moved_keyboard)
        checks = self.module.collect_checks(self.app, runner=self.runner)
        self.assertEqual(checks[-1].name, "keyboard")
        self.assertEqual(checks[-1].status, "fail")
        moved_keyboard.rename(keyboard)

        app_plist_path = self.app / "Info.plist"
        app_plist = self.read_plist(app_plist_path)
        app_plist["CFBundleExecutable"] = "UnexpectedExecutable"
        self.write_plist(app_plist_path, app_plist)
        (keyboard / "HoldTypeKeyboard").unlink()

        checks = self.checks_by_name()

        self.assertEqual(checks["app:executable-name"].status, "fail")
        self.assertEqual(checks["keyboard:executable"].status, "fail")

    def test_fails_closed_on_privacy_and_plist_boundary_regressions(self) -> None:
        (self.app / "Assets.car").unlink()
        (self.app / "PlugIns" / "HoldTypeKeyboard.appex" / "PrivacyInfo.xcprivacy").unlink()
        app_plist_path = self.app / "Info.plist"
        app_plist = self.read_plist(app_plist_path)
        app_plist["NSSpeechRecognitionUsageDescription"] = "speech"
        app_plist["UIBackgroundModes"] = ["audio"]
        self.write_plist(app_plist_path, app_plist)
        keyboard_plist_path = (
            self.app / "PlugIns" / "HoldTypeKeyboard.appex" / "Info.plist"
        )
        keyboard_plist = self.read_plist(keyboard_plist_path)
        keyboard_plist["NSMicrophoneUsageDescription"] = "microphone"
        extension = keyboard_plist["NSExtension"]
        if not isinstance(extension, dict):
            raise AssertionError("fixture extension is not a dictionary")
        attributes = extension["NSExtensionAttributes"]
        if not isinstance(attributes, dict):
            raise AssertionError("fixture attributes are not a dictionary")
        attributes["RequestsOpenAccess"] = True
        self.write_plist(keyboard_plist_path, keyboard_plist)

        checks = self.checks_by_name()

        for name in (
            "app:assets-catalog",
            "keyboard:privacy-manifest",
            "app:speech-purpose",
            "app:background-modes",
            "keyboard:microphone-purpose",
            "keyboard:open-access",
        ):
            self.assertEqual(checks[name].status, "fail", name)

    def test_rejects_exact_privacy_manifest_contract_drift(self) -> None:
        app_manifest_path = self.app / "PrivacyInfo.xcprivacy"
        app_manifest = self.read_plist(app_manifest_path)
        accessed = app_manifest["NSPrivacyAccessedAPITypes"]
        if not isinstance(accessed, list) or not isinstance(accessed[0], dict):
            raise AssertionError("fixture accessed API contract is invalid")
        accessed[0]["NSPrivacyAccessedAPITypeReasons"] = ["35F9.1"]
        self.write_plist(app_manifest_path, app_manifest)

        keyboard_manifest_path = (
            self.app
            / "PlugIns"
            / "HoldTypeKeyboard.appex"
            / "PrivacyInfo.xcprivacy"
        )
        keyboard_manifest = self.read_plist(keyboard_manifest_path)
        keyboard_manifest["NSPrivacyCollectedDataTypes"] = [
            {
                "NSPrivacyCollectedDataType": (
                    "NSPrivacyCollectedDataTypeOtherUserContent"
                )
            }
        ]
        self.write_plist(keyboard_manifest_path, keyboard_manifest)

        checks = self.checks_by_name()

        self.assertEqual(
            checks["app:privacy-manifest:contract"].status,
            "fail",
        )
        self.assertEqual(
            checks["keyboard:privacy-manifest:contract"].status,
            "fail",
        )

    def test_rejects_missing_or_translucent_compiled_app_icons(self) -> None:
        (self.app / "AppIcon60x60@2x.png").unlink()
        translucent = self.app / "AppIcon76x76@2x~ipad.png"
        self.write_png(translucent, 152, 152, color_type=6)

        checks = self.checks_by_name()

        self.assertEqual(checks["app:icon:iphone"].status, "fail")
        self.assertEqual(checks["app:icon:ipad"].status, "fail")

    def test_rejects_internal_ui_markers_in_executable_or_bundle_resource(self) -> None:
        app_executable = self.app / "HoldType-iOS"
        self.write_mach_o(
            app_executable,
            b"KeyboardBridgeProbeViewIOSProviderConsentQualificationFixture",
        )
        (self.app / "qualification.txt").write_text("Qualification Gallery")

        checks = self.checks_by_name()

        check = checks["app:internal-ui-markers"]
        self.assertEqual(check.status, "fail")
        self.assertIn("KeyboardBridgeProbeView", check.message)
        self.assertIn("IOSProviderConsentQualificationFixture", check.message)
        self.assertIn("Qualification Gallery", check.message)

    def test_requires_exact_codesign_bundle_identifiers(self) -> None:
        def executable_identifier_runner(command):
            if command[0] == "codesign" and "-d" in command:
                executable = Path(command[-1])
                return self.module.ToolResult(
                    0,
                    stderr=(
                        f"Executable={executable}\n"
                        f"Identifier={executable.name}\n"
                        "CodeDirectory v=20400 size=100 flags=0x2(adhoc)\n"
                        "CDHash=0123456789abcdef\n"
                    ),
                )
            return self.runner(command)

        checks = self.checks_by_name(runner=executable_identifier_runner)

        self.assertEqual(checks["app:signature:identifier"].status, "fail")
        self.assertEqual(
            checks["keyboard:signature:identifier"].status,
            "fail",
        )

    def test_rejects_keyboard_dependencies_symbols_strings_and_embedded_code(self) -> None:
        keyboard = self.app / "PlugIns" / "HoldTypeKeyboard.appex"
        framework = keyboard / "Frameworks" / "Injected.framework"
        framework.mkdir(parents=True)
        self.write_mach_o(framework / "Injected")
        self.write_mach_o(keyboard / "HoldTypeKeyboard", b"api.openai.com")

        def contaminated_runner(command):
            if command[0] == "otool":
                return self.module.ToolResult(
                    0,
                    stdout=(
                        f"{command[-1]}:\n"
                        "\t@rpath/HoldTypeOpenAI.framework/HoldTypeOpenAI "
                        "(compatibility version 1.0.0, current version 1.0.0)\n"
                    ),
                )
            if command[0] == "nm":
                return self.module.ToolResult(0, stdout="_OBJC_CLASS_$_AVAudioSession\n")
            if command[0] == "strings":
                return self.module.ToolResult(0, stdout="HoldTypePersistence\n")
            return self.runner(command)

        checks = self.checks_by_name(runner=contaminated_runner)

        for name in (
            "keyboard:embedded-dependencies",
            "keyboard:embedded-executables",
            "keyboard:dependencies:system-only",
            "keyboard:symbols:forbidden",
            "keyboard:strings:forbidden",
            "keyboard:bytes:forbidden",
        ):
            self.assertEqual(checks[name].status, "fail", name)

    def test_verifies_bundle_seal_when_signature_resources_are_present(self) -> None:
        for bundle in (
            self.app,
            self.app / "PlugIns" / "HoldTypeKeyboard.appex",
        ):
            signature = bundle / "_CodeSignature"
            signature.mkdir()
            (signature / "CodeResources").write_bytes(b"signature")

        def failing_verify_runner(command):
            if command[0] == "codesign" and "--verify" in command:
                return self.module.ToolResult(1, stderr="invalid signature")
            return self.runner(command)

        checks = self.checks_by_name(runner=failing_verify_runner)

        self.assertEqual(checks["app:signature:verification"].status, "fail")
        self.assertEqual(checks["keyboard:signature:verification"].status, "fail")

    def test_validates_processed_app_group_when_entitlements_are_available(self) -> None:
        exact_entitlements = plistlib.dumps(
            {
                "com.apple.security.application-groups": [
                    self.module.SHARED_APP_GROUP
                ]
            }
        ).decode("utf-8")

        def entitled_runner(command):
            if command[0] == "codesign" and "--entitlements" in command:
                return self.module.ToolResult(0, stdout=exact_entitlements)
            return self.runner(command)

        checks = self.checks_by_name(runner=entitled_runner)

        self.assertEqual(checks["app:processed-entitlements"].status, "pass")
        self.assertEqual(
            checks["keyboard:processed-entitlements"].status,
            "pass",
        )

    def test_rejects_wrong_processed_app_group(self) -> None:
        wrong_entitlements = plistlib.dumps(
            {
                "com.apple.security.application-groups": [
                    "group.example.unexpected"
                ]
            }
        ).decode("utf-8")

        def wrong_group_runner(command):
            if command[0] == "codesign" and "--entitlements" in command:
                return self.module.ToolResult(0, stdout=wrong_entitlements)
            return self.runner(command)

        checks = self.checks_by_name(runner=wrong_group_runner)

        self.assertEqual(checks["app:processed-entitlements"].status, "fail")
        self.assertEqual(
            checks["keyboard:processed-entitlements"].status,
            "fail",
        )

    def test_cli_accepts_explicit_manual_boundary_and_emits_json(self) -> None:
        stdout = io.StringIO()
        arguments = [
            str(SCRIPT_PATH),
            "--app",
            str(self.app),
            "--allow-manual",
            "--json",
        ]
        with (
            mock.patch.object(sys, "argv", arguments),
            mock.patch.object(self.module, "run_command", side_effect=self.runner),
            contextlib.redirect_stdout(stdout),
        ):
            exit_code = self.module.main()

        self.assertEqual(exit_code, 0)
        self.assertIn('"name": "app"', stdout.getvalue())
        self.assertIn('"status": "pass"', stdout.getvalue())

    def test_cli_returns_two_when_manual_checks_are_not_allowed(self) -> None:
        arguments = [str(SCRIPT_PATH), "--app", str(self.app)]
        with (
            mock.patch.object(sys, "argv", arguments),
            mock.patch.object(self.module, "run_command", side_effect=self.runner),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            exit_code = self.module.main()

        self.assertEqual(exit_code, 2)

    def test_tool_failure_is_a_verification_failure(self) -> None:
        def failing_runner(command):
            if command[0] in {"otool", "codesign"}:
                return self.module.ToolResult(124, stderr="timed out")
            return self.runner(command)

        checks = self.checks_by_name(runner=failing_runner)

        self.assertEqual(checks["keyboard:dependencies"].status, "fail")
        self.assertEqual(checks["keyboard:signature:metadata"].status, "fail")
        self.assertEqual(checks["app:signature:metadata"].status, "fail")


if __name__ == "__main__":
    unittest.main()
