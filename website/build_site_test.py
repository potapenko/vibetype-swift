#!/usr/bin/env python3
"""Tests for the deterministic localized landing-page builder."""

from __future__ import annotations

import importlib.util
import json
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path


WEBSITE_DIR = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("holdtype_build_site", WEBSITE_DIR / "build_site.py")
assert SPEC is not None and SPEC.loader is not None
build_site = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build_site)


class PageProbe(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.html_attributes: dict[str, str | None] = {}
        self.links: list[dict[str, str | None]] = []
        self.language_links: list[dict[str, str | None]] = []
        self.lightbox_links: list[dict[str, str | None]] = []
        self.lightbox_link_image_count = 0
        self.metadata: list[dict[str, str | None]] = []
        self.title_parts: list[str] = []
        self.in_title = False
        self.in_lightbox_link = False

    @property
    def title(self) -> str:
        return "".join(self.title_parts).strip()

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = dict(attrs)
        if tag == "html":
            self.html_attributes = attributes
        elif tag == "title":
            self.in_title = True
        elif tag == "link":
            self.links.append(attributes)
        elif tag == "meta":
            self.metadata.append(attributes)
        elif tag == "a" and "data-locale-link" in attributes:
            self.language_links.append(attributes)
        elif tag == "a" and "data-lightbox-link" in attributes:
            self.lightbox_links.append(attributes)
            self.in_lightbox_link = True
        elif tag == "img" and self.in_lightbox_link:
            self.lightbox_link_image_count += 1

    def handle_endtag(self, tag: str) -> None:
        if tag == "title":
            self.in_title = False
        elif tag == "a" and self.in_lightbox_link:
            self.in_lightbox_link = False

    def handle_data(self, data: str) -> None:
        if self.in_title:
            self.title_parts.append(data)


class BuildSiteTests(unittest.TestCase):
    maxDiff = None

    def build_actual_site(self, output: Path) -> list[Path]:
        return build_site.build_site(source_dir=WEBSITE_DIR, output_dir=output)

    def copied_source(self, root: Path) -> Path:
        source = root / "website"
        shutil.copytree(WEBSITE_DIR, source, ignore=shutil.ignore_patterns("__pycache__"))
        return source

    def test_builds_exact_static_locale_routes_and_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "public"
            written = self.build_actual_site(output)

            expected_root = {
                "index.html",
                "styles.css",
                "script.js",
                "sitemap.xml",
                "robots.txt",
                "assets",
                "ar",
                "de",
                "es",
                "fr",
                "ja",
                "ko",
                "pt-br",
                "ru",
                "zh-hans",
            }
            self.assertEqual({path.name for path in output.iterdir()}, expected_root)
            self.assertFalse((output / "en").exists())
            self.assertGreater(len(written), 20)

            expected_locales = {
                "en": ("", "ltr", "en_US"),
                "es": ("es", "ltr", "es_ES"),
                "de": ("de", "ltr", "de_DE"),
                "fr": ("fr", "ltr", "fr_FR"),
                "pt-BR": ("pt-br", "ltr", "pt_BR"),
                "ja": ("ja", "ltr", "ja_JP"),
                "zh-Hans": ("zh-hans", "ltr", "zh_CN"),
                "ko": ("ko", "ltr", "ko_KR"),
                "ru": ("ru", "ltr", "ru_RU"),
                "ar": ("ar", "rtl", "ar_AR"),
            }
            expected_alternates = {
                code: f"https://holdtype.app/{route}/" if route else "https://holdtype.app/"
                for code, (route, _, _) in expected_locales.items()
            }
            expected_alternates["x-default"] = "https://holdtype.app/"

            rendered_pages: dict[str, str] = {}
            for code, (route, direction, open_graph_locale) in expected_locales.items():
                page = output / route / "index.html" if route else output / "index.html"
                asset_prefix = "../" if route else ""
                rendered = page.read_text(encoding="utf-8")
                rendered_pages[code] = rendered
                probe = PageProbe()
                probe.feed(rendered)

                canonical_url = expected_alternates[code]
                self.assertEqual(probe.html_attributes["lang"], code)
                self.assertEqual(probe.html_attributes.get("dir", "ltr"), direction)
                self.assertEqual(probe.html_attributes["data-site-locale"], code)
                self.assertEqual(
                    [link["href"] for link in probe.links if link.get("rel") == "canonical"],
                    [canonical_url],
                )
                self.assertEqual(
                    {
                        link["hreflang"]: link["href"]
                        for link in probe.links
                        if link.get("rel") == "alternate"
                    },
                    expected_alternates,
                )
                self.assertEqual(len(probe.language_links), 10)
                self.assertEqual(
                    {link["hreflang"] for link in probe.language_links},
                    set(expected_locales),
                )
                self.assertEqual(len(probe.lightbox_links), 2)
                self.assertEqual(probe.lightbox_link_image_count, 2)
                self.assertEqual(
                    {link["href"] for link in probe.lightbox_links},
                    {
                        f"{asset_prefix}assets/settings-billing.png",
                        f"{asset_prefix}assets/settings-translation.png",
                    },
                )

                metadata = {
                    item.get("property") or item.get("name"): item.get("content")
                    for item in probe.metadata
                    if item.get("property") or item.get("name")
                }
                self.assertTrue(probe.title)
                self.assertTrue(metadata["description"])
                self.assertEqual(metadata["og:title"], probe.title)
                self.assertEqual(metadata["twitter:title"], probe.title)
                self.assertEqual(metadata["og:description"], metadata["description"])
                self.assertEqual(metadata["twitter:description"], metadata["description"])
                self.assertEqual(metadata["og:url"], canonical_url)
                self.assertEqual(metadata["og:locale"], open_graph_locale)
                self.assertEqual(metadata["og:image"], build_site.SOCIAL_PREVIEW_URL)
                self.assertEqual(metadata["og:image:secure_url"], build_site.SOCIAL_PREVIEW_URL)
                self.assertEqual(metadata["og:image:type"], "image/png")
                self.assertEqual(metadata["og:image:width"], "1200")
                self.assertEqual(metadata["og:image:height"], "630")
                self.assertTrue(metadata["og:image:alt"])
                self.assertEqual(metadata["twitter:card"], "summary_large_image")
                self.assertEqual(metadata["twitter:image"], build_site.SOCIAL_PREVIEW_URL)
                self.assertEqual(metadata["twitter:image:alt"], metadata["og:image:alt"])

                self.assertNotIn("data-i18n", rendered)
                self.assertNotIn("data-token-ref", rendered)
                self.assertNotIn("data-site-og-image", rendered)
                self.assertNotIn("data-locale-config", rendered)
                self.assertIn("data-language-suggestion-text", rendered)

            root_html = rendered_pages["en"]
            russian_html = rendered_pages["ru"]
            arabic_html = rendered_pages["ar"]
            self.assertIn('href="../styles.css"', russian_html)
            self.assertIn('src="../script.js"', russian_html)
            self.assertIn("\u2066HoldType\u2069", arabic_html)
            self.assertIn('<bdi lang="en" dir="ltr">Billing</bdi>', arabic_html)
            self.assertIn('<bdi dir="ltr">HoldType</bdi>', arabic_html)
            self.assertIn("data-lightbox-caption=", arabic_html)

            config_start = russian_html.index('<script type="application/json" id="locale-config">')
            config_start = russian_html.index(">", config_start) + 1
            config_end = russian_html.index("</script>", config_start)
            config = json.loads(russian_html[config_start:config_end])
            self.assertEqual(config["currentLocale"], "ru")
            self.assertFalse(config["isDefaultRoute"])
            self.assertEqual(len(config["locales"]), 10)
            self.assertEqual(config["assetPrefix"], "../assets/")
            russian_suggestion = next(
                locale for locale in config["locales"] if locale["code"] == "ru"
            )
            self.assertEqual(russian_suggestion["suggestionDismiss"], "Не сейчас")
            self.assertTrue(russian_suggestion["suggestionDismissAria"])
            self.assertTrue(russian_suggestion["suggestionAria"])

            sitemap_root = ET.fromstring((output / "sitemap.xml").read_text(encoding="utf-8"))
            namespaces = {
                "sitemap": "http://www.sitemaps.org/schemas/sitemap/0.9",
                "xhtml": "http://www.w3.org/1999/xhtml",
            }
            sitemap_urls = sitemap_root.findall("sitemap:url", namespaces)
            self.assertEqual(len(sitemap_urls), 10)
            self.assertEqual(
                {
                    item.findtext("sitemap:loc", namespaces=namespaces)
                    for item in sitemap_urls
                },
                set(expected_alternates.values()),
            )
            for item in sitemap_urls:
                self.assertEqual(
                    {
                        link.attrib["hreflang"]: link.attrib["href"]
                        for link in item.findall("xhtml:link", namespaces)
                    },
                    expected_alternates,
                )
            self.assertEqual(
                (output / "robots.txt").read_text(encoding="utf-8"),
                "User-agent: *\nAllow: /\nSitemap: https://holdtype.app/sitemap.xml\n",
            )
            self.assertEqual(
                build_site.read_png_dimensions(
                    output / "assets" / build_site.SOCIAL_PREVIEW_FILENAME
                ),
                build_site.SOCIAL_PREVIEW_DIMENSIONS,
            )

    def test_requires_exact_social_preview_asset(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.copied_source(root)
            preview = source / "assets" / build_site.SOCIAL_PREVIEW_FILENAME
            preview.unlink()

            with self.assertRaisesRegex(build_site.SiteBuildError, "required website source"):
                build_site.build_site(source_dir=source, output_dir=root / "missing-output")

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.copied_source(root)
            preview = source / "assets" / build_site.SOCIAL_PREVIEW_FILENAME
            shutil.copyfile(source / "assets" / "app-icon.png", preview)

            with self.assertRaisesRegex(build_site.SiteBuildError, "must be 1200x630"):
                build_site.build_site(source_dir=source, output_dir=root / "wrong-size-output")

    def test_rejects_missing_translation_key(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.copied_source(root)
            catalog_path = source / "i18n" / "es.json"
            catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
            del catalog["header"]["faq"]
            catalog_path.write_text(json.dumps(catalog, ensure_ascii=False), encoding="utf-8")

            with self.assertRaisesRegex(build_site.SiteBuildError, "key mismatch"):
                build_site.build_site(source_dir=source, output_dir=root / "public")

    def test_pricing_examples_do_not_label_message_length(self) -> None:
        forbidden_phrases = {
            "en": ("quick messages", "short messages", "average messages"),
            "es": ("mensajes rápidos", "mensajes cortos", "mensajes promedio"),
            "de": ("kurze Nachrichten", "schnelle Nachrichten", "durchschnittliche Nachrichten"),
            "fr": ("messages courts", "messages rapides", "messages moyens"),
            "pt-BR": ("mensagens rápidas", "mensagens curtas", "mensagens médias"),
            "ja": ("短いメッセージ", "平均的なメッセージ"),
            "zh-Hans": ("短消息", "平均消息"),
            "ko": ("짧은 메시지", "평균 메시지"),
            "ru": ("коротких сообщений", "длинных сообщений", "средних сообщений"),
            "ar": ("رسالة سريعة", "رسالة قصيرة", "رسالة متوسطة"),
        }

        for locale, phrases in forbidden_phrases.items():
            catalog = json.loads(
                (WEBSITE_DIR / "i18n" / f"{locale}.json").read_text(encoding="utf-8")
            )
            billing = catalog["privacy"]["billing"]
            pricing_copy = f'{billing["exampleTitle"]} {billing["exampleBody"]}'
            for phrase in phrases:
                with self.subTest(locale=locale, phrase=phrase):
                    self.assertNotIn(phrase, pricing_copy)

    def test_rejects_raw_html_in_translation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.copied_source(root)
            catalog_path = source / "i18n" / "de.json"
            catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
            catalog["header"]["menuClosed"] = "<b>Menü</b>"
            catalog_path.write_text(json.dumps(catalog, ensure_ascii=False), encoding="utf-8")

            with self.assertRaisesRegex(build_site.SiteBuildError, "contains raw HTML"):
                build_site.build_site(source_dir=source, output_dir=root / "public")

    def test_rejects_translated_rich_link_reference_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.copied_source(root)
            catalog_path = source / "i18n" / "es.json"
            catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
            catalog["apiKeyGuide"]["steps"]["openPage"]["parts"][1]["ref"] = (
                "openAIKeyHelp"
            )
            catalog_path.write_text(json.dumps(catalog, ensure_ascii=False), encoding="utf-8")

            with self.assertRaisesRegex(build_site.SiteBuildError, "link references differ"):
                build_site.build_site(source_dir=source, output_dir=root / "public")

    def test_requires_empty_output_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "public"
            output.mkdir()
            (output / "stale.txt").write_text("stale", encoding="utf-8")
            with self.assertRaisesRegex(build_site.SiteBuildError, "must be empty"):
                self.build_actual_site(output)

    @unittest.skipUnless(shutil.which("node"), "Node.js is not available")
    def test_locale_runtime_matching(self) -> None:
        result = subprocess.run(
            ["node", str(WEBSITE_DIR / "script_runtime_test.mjs")],
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
