#!/usr/bin/env python3
"""Build the complete static HoldType landing site for every supported locale."""

from __future__ import annotations

import argparse
import html
import json
import re
import shutil
import sys
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence


CANONICAL_ORIGIN = "https://holdtype.app"
SOCIAL_PREVIEW_FILENAME = "holdtype-social-preview.png"
SOCIAL_PREVIEW_DIMENSIONS = (1200, 630)
SOCIAL_PREVIEW_URL = f"{CANONICAL_ORIGIN}/assets/{SOCIAL_PREVIEW_FILENAME}"
EXPECTED_LOCALE_ROUTES = {
    "en": "",
    "es": "es",
    "de": "de",
    "fr": "fr",
    "pt-BR": "pt-br",
    "ja": "ja",
    "zh-Hans": "zh-hans",
    "ko": "ko",
    "ru": "ru",
    "ar": "ar",
}
ROOT_PUBLIC_FILES = ("index.html", "styles.css", "script.js", "sitemap.xml", "robots.txt")
RUNTIME_MESSAGE_KEYS = (
    "header.menuClosed",
    "header.menuOpen",
    "hero.demo.status.listening",
    "hero.demo.status.transcribing",
    "hero.demo.status.inserted",
    "install.homebrew.copyIdle",
    "install.homebrew.copyCopied",
    "install.homebrew.copyRetry",
    "install.homebrew.copySuccessStatus",
    "install.homebrew.copyFailureStatus",
    "apiKeyGuide.video.fallbackIframeTitle",
    "lightbox.fallbackImageAlt",
)
SUGGESTION_MESSAGE_KEYS = (
    "localeUi.suggestionMessage",
    "localeUi.suggestionAction",
    "localeUi.suggestionDismiss",
    "localeUi.suggestionAria",
    "localeUi.suggestionDismissAria",
)
VOID_ELEMENTS = {
    "area",
    "base",
    "br",
    "col",
    "embed",
    "hr",
    "img",
    "input",
    "link",
    "meta",
    "param",
    "source",
    "track",
    "wbr",
}
IGNORED_TEXT_ELEMENTS = {"code", "kbd", "path", "pre", "script", "style", "svg"}
LANGUAGE_BEARING_ATTRIBUTES = {
    "alt",
    "aria-label",
    "data-lightbox-caption",
    "data-video-title",
    "title",
}
TOKEN_PATTERN = re.compile(
    r"\{([A-Za-z][A-Za-z0-9]*(?:\.[A-Za-z][A-Za-z0-9]*)*)\}"
)
STRUCTURAL_TEXT_PATTERN = re.compile(r"^(?:[0-9]+|[×⌘]|[.·…,:]+|Aa\s*···)$")


class SiteBuildError(RuntimeError):
    """Raised when the localized static artifact cannot be built safely."""


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SiteBuildError(f"could not read JSON {path}: {error}") from error


def read_png_dimensions(path: Path) -> tuple[int, int]:
    try:
        with path.open("rb") as image_file:
            header = image_file.read(24)
    except OSError as error:
        raise SiteBuildError(f"could not read PNG {path}: {error}") from error
    if (
        len(header) != 24
        or header[:8] != b"\x89PNG\r\n\x1a\n"
        or header[12:16] != b"IHDR"
    ):
        raise SiteBuildError(f"social preview must be a valid PNG: {path}")
    return int.from_bytes(header[16:20], "big"), int.from_bytes(header[20:24], "big")


def is_rich_message(value: Any) -> bool:
    return isinstance(value, dict) and set(value) == {"parts"} and isinstance(value["parts"], list)


def flatten_messages(value: Any, *, prefix: str = "") -> dict[str, Any]:
    if isinstance(value, str) or is_rich_message(value):
        if not prefix:
            raise SiteBuildError("locale catalog root must be an object")
        return {prefix: value}
    if not isinstance(value, dict) or not value:
        raise SiteBuildError(f"locale catalog node {prefix or '<root>'!r} must be a non-empty object")

    flattened: dict[str, Any] = {}
    for key, child in value.items():
        if not isinstance(key, str) or not re.fullmatch(r"[A-Za-z][A-Za-z0-9]*", key):
            raise SiteBuildError(f"invalid locale catalog key {key!r} below {prefix or '<root>'}")
        child_prefix = f"{prefix}.{key}" if prefix else key
        flattened.update(flatten_messages(child, prefix=child_prefix))
    return flattened


def message_texts(value: Any) -> Iterable[str]:
    if isinstance(value, str):
        yield value
        return
    if not is_rich_message(value):
        raise SiteBuildError(f"unsupported message value: {value!r}")
    for part in value["parts"]:
        if not isinstance(part, dict) or part.get("type") not in {"text", "link"}:
            raise SiteBuildError(f"unsupported rich message part: {part!r}")
        field = "value" if part["type"] == "text" else "text"
        text = part.get(field)
        if not isinstance(text, str) or not text.strip():
            raise SiteBuildError(f"rich message part has no {field}: {part!r}")
        yield text


def placeholder_counter(value: Any) -> Counter[str]:
    result: Counter[str] = Counter()
    for text in message_texts(value):
        result.update(TOKEN_PATTERN.findall(text))
    return result


def validate_rich_shape(key: str, reference: Any, candidate: Any, links: Mapping[str, Any]) -> None:
    if is_rich_message(reference) != is_rich_message(candidate):
        raise SiteBuildError(f"message type differs from English for {key}")
    if not is_rich_message(reference):
        return

    reference_parts = reference["parts"]
    candidate_parts = candidate["parts"]
    if [part.get("type") for part in reference_parts] != [part.get("type") for part in candidate_parts]:
        raise SiteBuildError(f"rich message segment types differ from English for {key}")
    for reference_part, part in zip(reference_parts, candidate_parts):
        if part["type"] != "link":
            if set(part) != {"type", "value"}:
                raise SiteBuildError(f"unexpected text segment fields for {key}: {part!r}")
            continue
        if set(part) != {"type", "ref", "text"}:
            raise SiteBuildError(f"unexpected link segment fields for {key}: {part!r}")
        ref = part.get("ref")
        if not isinstance(ref, str) or ref not in links:
            raise SiteBuildError(f"unknown rich link reference {ref!r} for {key}")
        if ref != reference_part.get("ref"):
            raise SiteBuildError(f"rich link references differ from English for {key}")


def expand_tokens(text: str, tokens: Mapping[str, str], *, key: str) -> str:
    def replace(match: re.Match[str]) -> str:
        token = match.group(1)
        try:
            return tokens[token]
        except KeyError as error:
            raise SiteBuildError(f"unknown token {{{token}}} in {key}") from error

    return TOKEN_PATTERN.sub(replace, text)


def render_message_html(
    text: str,
    tokens: Mapping[str, str],
    markup_tokens: Mapping[str, str],
    *,
    key: str,
) -> str:
    rendered: list[str] = []
    cursor = 0
    for match in TOKEN_PATTERN.finditer(text):
        rendered.append(html.escape(text[cursor : match.start()], quote=False))
        token = match.group(1)
        if token not in tokens or token not in markup_tokens:
            raise SiteBuildError(f"unknown token {{{token}}} in {key}")
        rendered.append(markup_tokens[token])
        cursor = match.end()
    rendered.append(html.escape(text[cursor:], quote=False))
    return "".join(rendered)


def render_plain_message(
    value: Any,
    tokens: Mapping[str, str],
    markup_tokens: Mapping[str, str],
    *,
    key: str,
) -> str:
    if not isinstance(value, str):
        raise SiteBuildError(f"plain message marker {key} points to rich content")
    return render_message_html(value, tokens, markup_tokens, key=key)


def render_rich_message(
    value: Any,
    tokens: Mapping[str, str],
    markup_tokens: Mapping[str, str],
    links: Mapping[str, Any],
    messages: Mapping[str, Any],
    used_message_keys: set[str],
    *,
    key: str,
    path_prefix: str,
) -> str:
    if not is_rich_message(value):
        raise SiteBuildError(f"rich message marker {key} points to plain content")

    rendered: list[str] = []
    for part in value["parts"]:
        if part["type"] == "text":
            rendered.append(render_message_html(part["value"], tokens, markup_tokens, key=key))
            continue

        ref = part["ref"]
        link = links[ref]
        if not isinstance(link, dict) or not isinstance(link.get("href"), str):
            raise SiteBuildError(f"invalid trusted link {ref!r}")
        href = link["href"]
        if href.startswith("assets/"):
            href = path_prefix + href
        attrs = {"href": href}
        extra_attrs = link.get("attrs", {})
        if not isinstance(extra_attrs, dict):
            raise SiteBuildError(f"invalid attrs for trusted link {ref!r}")
        for name, attribute_value in extra_attrs.items():
            if not isinstance(name, str) or not isinstance(attribute_value, str):
                raise SiteBuildError(f"invalid attribute for trusted link {ref!r}")
            attrs[name] = attribute_value
        localized_attrs = link.get("localizedAttrs", {})
        if not isinstance(localized_attrs, dict):
            raise SiteBuildError(f"invalid localized attrs for trusted link {ref!r}")
        for name, message_key in localized_attrs.items():
            if not isinstance(name, str) or not isinstance(message_key, str):
                raise SiteBuildError(f"invalid localized attribute for trusted link {ref!r}")
            message = messages.get(message_key)
            if not isinstance(message, str):
                raise SiteBuildError(
                    f"localized attribute {message_key!r} for trusted link {ref!r} "
                    "must point to a plain message"
                )
            attrs[name] = expand_tokens(message, tokens, key=message_key)
            used_message_keys.add(message_key)
        attrs_text = "".join(
            f' {name}="{html.escape(attribute_value, quote=True)}"'
            for name, attribute_value in attrs.items()
        )
        label = render_message_html(part["text"], tokens, markup_tokens, key=key)
        rendered.append(f"<a{attrs_text}>{label}</a>")
    return "".join(rendered)


def locale_url(route: str) -> str:
    return f"{CANONICAL_ORIGIN}/{route}/" if route else f"{CANONICAL_ORIGIN}/"


def relative_locale_href(current_route: str, target_route: str) -> str:
    prefix = "../" if current_route else ""
    if not target_route:
        return prefix or "./"
    return f"{prefix}{target_route}/"


def render_hreflang_links(locales: Sequence[Mapping[str, Any]]) -> str:
    lines = [
        f'<link rel="alternate" hreflang="{html.escape(locale["code"], quote=True)}" '
        f'href="{html.escape(locale_url(locale["path"]), quote=True)}">'
        for locale in locales
    ]
    lines.append(f'<link rel="alternate" hreflang="x-default" href="{CANONICAL_ORIGIN}/">')
    return "\n    ".join(lines)


def render_language_links(
    locales: Sequence[Mapping[str, Any]], *, current: Mapping[str, Any]
) -> str:
    lines: list[str] = []
    for locale in locales:
        attrs = {
            "href": relative_locale_href(current["path"], locale["path"]),
            "hreflang": locale["code"],
            "lang": locale["code"],
            "dir": locale["dir"],
            "data-locale-link": "",
            "data-locale": locale["code"],
        }
        if locale["code"] == current["code"]:
            attrs["aria-current"] = "page"
        attrs_text = "".join(
            f" {name}" if value == "" else f' {name}="{html.escape(value, quote=True)}"'
            for name, value in attrs.items()
        )
        lines.append(
            f"<li><a{attrs_text}>{html.escape(locale['nativeName'], quote=False)}</a></li>"
        )
    return "\n              ".join(lines)


def runtime_payload(
    *,
    current: Mapping[str, Any],
    locales: Sequence[Mapping[str, Any]],
    catalogs: Mapping[str, Mapping[str, Any]],
    tokens: Mapping[str, str],
) -> str:
    current_messages = catalogs[current["code"]]
    strings = {
        key: expand_tokens(current_messages[key], tokens, key=key)
        for key in RUNTIME_MESSAGE_KEYS
    }
    locale_options = []
    for locale in locales:
        messages = catalogs[locale["code"]]
        locale_options.append(
            {
                "code": locale["code"],
                "href": relative_locale_href(current["path"], locale["path"]),
                "nativeName": locale["nativeName"],
                "dir": locale["dir"],
                "browserMatches": locale["browserMatches"],
                "suggestionMessage": expand_tokens(
                    messages["localeUi.suggestionMessage"],
                    tokens,
                    key="localeUi.suggestionMessage",
                ),
                "suggestionAction": expand_tokens(
                    messages["localeUi.suggestionAction"], tokens, key="localeUi.suggestionAction"
                ),
                "suggestionDismiss": expand_tokens(
                    messages["localeUi.suggestionDismiss"],
                    tokens,
                    key="localeUi.suggestionDismiss",
                ),
                "suggestionAria": expand_tokens(
                    messages["localeUi.suggestionAria"], tokens, key="localeUi.suggestionAria"
                ),
                "suggestionDismissAria": expand_tokens(
                    messages["localeUi.suggestionDismissAria"],
                    tokens,
                    key="localeUi.suggestionDismissAria",
                ),
            }
        )
    payload = {
        "currentLocale": current["code"],
        "defaultLocale": "en",
        "isDefaultRoute": current["code"] == "en",
        "assetPrefix": ("../" if current["path"] else "") + "assets/",
        "preferenceStorageKey": "holdtype.preferredLocale.v1",
        "dismissedSessionKey": "holdtype.localeSuggestionDismissed.v1",
        "strings": strings,
        "locales": locale_options,
    }
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":")).replace("<", "\\u003c")


def parse_attribute_markers(value: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for entry in value.split(";"):
        if not entry.strip():
            continue
        attribute, separator, key = entry.partition(":")
        if not separator or not attribute.strip() or not key.strip():
            raise SiteBuildError(f"invalid data-i18n-attrs entry: {entry!r}")
        result[attribute.strip()] = key.strip()
    return result


class LocalizedHTMLParser(HTMLParser):
    def __init__(
        self,
        *,
        locale: Mapping[str, Any],
        locales: Sequence[Mapping[str, Any]],
        messages: Mapping[str, Any],
        catalogs: Mapping[str, Mapping[str, Any]],
        tokens: Mapping[str, str],
        markup_tokens: Mapping[str, str],
        links: Mapping[str, Any],
        commands: Mapping[str, str],
        videos: Mapping[str, Any],
    ) -> None:
        super().__init__(convert_charrefs=False)
        self.locale = locale
        self.locales = locales
        self.messages = messages
        self.catalogs = catalogs
        self.tokens = tokens
        self.markup_tokens = markup_tokens
        self.links = links
        self.commands = commands
        self.videos = videos
        self.output: list[str] = []
        self.open_elements: list[str] = []
        self.replacement_tag: str | None = None
        self.suppressed_depth = 0
        self.used_message_keys: set[str] = set()
        self.generated_markers: Counter[str] = Counter()

    @property
    def path_prefix(self) -> str:
        return "../" if self.locale["path"] else ""

    def format_attrs(self, attrs: Sequence[tuple[str, str | None]]) -> str:
        return "".join(
            f" {name}" if value is None else f' {name}="{html.escape(value, quote=True)}"'
            for name, value in attrs
        )

    def localize_asset_path(self, name: str, value: str) -> str:
        if name in {"href", "src", "poster"} and (
            value in {"styles.css", "script.js"} or value.startswith("assets/")
        ):
            return self.path_prefix + value
        if name == "srcset":
            return value.replace("assets/", self.path_prefix + "assets/")
        return value

    def invariant_text(self, value: str) -> bool:
        normalized = " ".join(value.split())
        if not normalized:
            return True
        plain_token_values = {
            token.replace("\u2066", "").replace("\u2069", "")
            for token in self.tokens.values()
        }
        if normalized in plain_token_values:
            return True
        return STRUCTURAL_TEXT_PATTERN.fullmatch(normalized) is not None

    def handle_decl(self, decl: str) -> None:
        self.output.append(f"<!{decl}>")

    def handle_comment(self, data: str) -> None:
        marker = data.strip().replace("_", ":")
        if marker in {"SITE:HREFLANG", "SITE:HREFLANG:LINKS"}:
            self.generated_markers["hreflang"] += 1
            self.output.append(render_hreflang_links(self.locales))
        elif marker in {"SITE:LANGUAGE:LINKS", "SITE:LANGUAGE:LINKS:LINKS"}:
            self.generated_markers["languageLinks"] += 1
            self.output.append(render_language_links(self.locales, current=self.locale))
        elif marker in {"SITE:LOCALE:RUNTIME", "SITE:LOCALE:CONFIG"}:
            self.generated_markers["runtime"] += 1
            payload = runtime_payload(
                current=self.locale,
                locales=self.locales,
                catalogs=self.catalogs,
                tokens=self.tokens,
            )
            self.output.append(
                f'<script type="application/json" id="locale-runtime">{payload}</script>'
            )
        elif self.replacement_tag is None:
            self.output.append(f"<!--{data}-->")

    def trusted_link_href(self, ref: str) -> tuple[str, dict[str, str]]:
        link = self.links.get(ref)
        if not isinstance(link, dict) or not isinstance(link.get("href"), str):
            raise SiteBuildError(f"unknown trusted link reference: {ref!r}")
        href = link["href"]
        if href.startswith("assets/"):
            href = self.path_prefix + href
        extra_attrs = link.get("attrs", {})
        if not isinstance(extra_attrs, dict) or not all(
            isinstance(name, str) and isinstance(value, str)
            for name, value in extra_attrs.items()
        ):
            raise SiteBuildError(f"invalid trusted link attrs for {ref!r}")
        return href, extra_attrs

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        tag = tag.lower()
        if self.replacement_tag is not None:
            if tag not in VOID_ELEMENTS:
                self.suppressed_depth += 1
            return

        attrs_dict = dict(attrs)
        text_key = attrs_dict.get("data-i18n")
        rich_key = attrs_dict.get("data-i18n-rich")
        template_key = attrs_dict.get("data-i18n-template")
        if text_key and rich_key:
            raise SiteBuildError(f"element <{tag}> cannot have both data-i18n and data-i18n-rich")
        if sum(value is not None for value in (text_key, rich_key, template_key)) > 1:
            raise SiteBuildError(f"element <{tag}> has conflicting localization markers")

        attribute_markers = parse_attribute_markers(attrs_dict.get("data-i18n-attrs", ""))
        output_attrs: list[tuple[str, str | None]] = []
        for name, original_value in attrs:
            if name in {
                "data-i18n",
                "data-i18n-rich",
                "data-i18n-template",
                "data-i18n-attrs",
                "data-i18n-runtime",
                "data-command-ref",
                "data-link-ref",
                "data-locale-alternate",
                "data-locale-canonical",
                "data-locale-canonical-content",
                "data-locale-config",
                "data-locale-current-name",
                "data-locale-document",
                "data-locale-links",
                "data-locale-open-graph",
                "data-root-only",
                "data-token-attr",
                "data-token-ref",
                "data-video-ref",
            }:
                continue
            value = original_value
            if name in attribute_markers:
                key = attribute_markers[name]
                message = self.messages.get(key)
                if not isinstance(message, str):
                    raise SiteBuildError(f"attribute marker {key} must point to a plain message")
                value = expand_tokens(message, self.tokens, key=key)
                self.used_message_keys.add(key)
            if value is not None:
                value = self.localize_asset_path(name, value)
            output_attrs.append((name, value))

        output_names = {name for name, _ in output_attrs}
        for name, key in attribute_markers.items():
            if name not in output_names:
                message = self.messages.get(key)
                if not isinstance(message, str):
                    raise SiteBuildError(f"attribute marker {key} must point to a plain message")
                output_attrs.append((name, expand_tokens(message, self.tokens, key=key)))
                self.used_message_keys.add(key)

        token_attr_marker = attrs_dict.get("data-token-attr")
        if token_attr_marker:
            token_attr, separator, token_key = token_attr_marker.partition(":")
            if not separator or token_key not in self.tokens:
                raise SiteBuildError(f"invalid data-token-attr marker: {token_attr_marker!r}")
            output_attrs = [(name, value) for name, value in output_attrs if name != token_attr]
            output_attrs.append((token_attr, self.tokens[token_key]))

        link_ref = attrs_dict.get("data-link-ref")
        if link_ref:
            href, trusted_attrs = self.trusted_link_href(link_ref)
            output_attrs = [(name, value) for name, value in output_attrs if name != "href"]
            output_attrs.append(("href", href))
            existing_names = {name for name, _ in output_attrs}
            for name, value in trusted_attrs.items():
                if name not in existing_names:
                    output_attrs.append((name, value))

        video_ref = attrs_dict.get("data-video-ref")
        if video_ref:
            video = self.videos.get(video_ref)
            if not isinstance(video, dict) or not isinstance(video.get("id"), str):
                raise SiteBuildError(f"unknown trusted video reference: {video_ref!r}")
            output_attrs = [(name, value) for name, value in output_attrs if name != "data-video-id"]
            output_attrs.append(("data-video-id", video["id"]))

        if tag == "html":
            output_attrs = [
                (name, value)
                for name, value in output_attrs
                if name not in {"lang", "dir", "data-site-locale"}
            ]
            output_attrs.append(("lang", self.locale["code"]))
            if self.locale["dir"] == "rtl":
                output_attrs.append(("dir", "rtl"))
            output_attrs.append(("data-site-locale", self.locale["code"]))

        if "data-site-canonical" in attrs_dict or "data-locale-canonical" in attrs_dict:
            output_attrs = [(name, value) for name, value in output_attrs if name != "data-site-canonical"]
            output_attrs = [
                (name, locale_url(self.locale["path"]) if name == "href" else value)
                for name, value in output_attrs
            ]
        if "data-site-url" in attrs_dict or "data-locale-canonical-content" in attrs_dict:
            output_attrs = [(name, value) for name, value in output_attrs if name != "data-site-url"]
            output_attrs = [
                (name, locale_url(self.locale["path"]) if name == "content" else value)
                for name, value in output_attrs
            ]
        if "data-site-og-image" in attrs_dict:
            output_attrs = [(name, value) for name, value in output_attrs if name != "data-site-og-image"]
            output_attrs = [
                (name, SOCIAL_PREVIEW_URL if name == "content" else value)
                for name, value in output_attrs
            ]
        if "data-site-og-locale" in attrs_dict or "data-locale-open-graph" in attrs_dict:
            output_attrs = [(name, value) for name, value in output_attrs if name != "data-site-og-locale"]
            output_attrs = [
                (name, self.locale.get("ogLocale", self.locale["code"]) if name == "content" else value)
                for name, value in output_attrs
            ]

        alternate_code = attrs_dict.get("data-locale-alternate")
        if alternate_code:
            routes = {locale["code"]: locale["path"] for locale in self.locales}
            routes["x-default"] = ""
            if alternate_code not in routes:
                raise SiteBuildError(f"unknown hreflang locale marker: {alternate_code!r}")
            output_attrs = [(name, value) for name, value in output_attrs if name != "href"]
            output_attrs.append(("href", locale_url(routes[alternate_code])))
            self.generated_markers[f"alternate:{alternate_code}"] += 1

        if "data-site-current-language" in attrs_dict or "data-locale-current-name" in attrs_dict:
            output_attrs = [
                (name, value) for name, value in output_attrs if name != "data-site-current-language"
            ]
            if text_key or rich_key:
                raise SiteBuildError("current-language marker cannot also be translated")
            output_attrs.append(("data-current-language", ""))
            text_key = "__current_language__"

        token_ref = attrs_dict.get("data-token-ref")
        if token_ref:
            if token_ref not in self.tokens:
                raise SiteBuildError(f"unknown data-token-ref marker: {token_ref!r}")
            if text_key or rich_key or template_key:
                raise SiteBuildError("token marker cannot also be translated")
            text_key = "__token__"

        command_ref = attrs_dict.get("data-command-ref")
        if command_ref:
            if command_ref not in self.commands:
                raise SiteBuildError(f"unknown data-command-ref marker: {command_ref!r}")
            if text_key or rich_key or template_key:
                raise SiteBuildError("command marker cannot also be translated")
            text_key = "__command__"

        if "data-locale-links" in attrs_dict:
            if text_key or rich_key or template_key:
                raise SiteBuildError("locale-links marker cannot also be translated")
            text_key = "__language_links__"

        if "data-locale-config" in attrs_dict:
            if tag != "script" or text_key or rich_key or template_key:
                raise SiteBuildError("locale-config marker must be the only content marker on script")
            text_key = "__locale_config__"

        if template_key:
            if template_key not in self.messages:
                raise SiteBuildError(f"missing template message {template_key}")
            text_key = "__template__"

        self.output.append(f"<{tag}{self.format_attrs(output_attrs)}>")
        if tag not in VOID_ELEMENTS:
            self.open_elements.append(tag)

        if text_key or rich_key:
            if tag in VOID_ELEMENTS:
                raise SiteBuildError(f"content message marker cannot be placed on void element <{tag}>")
            if text_key == "__current_language__":
                self.output.append(html.escape(self.locale["nativeName"], quote=False))
            elif text_key == "__token__":
                assert token_ref is not None
                self.output.append(self.markup_tokens[token_ref])
            elif text_key == "__command__":
                assert command_ref is not None
                self.output.append(html.escape(self.commands[command_ref], quote=False))
            elif text_key == "__language_links__":
                self.output.append(render_language_links(self.locales, current=self.locale))
                self.generated_markers["languageLinks"] += 1
            elif text_key == "__locale_config__":
                self.output.append(
                    runtime_payload(
                        current=self.locale,
                        locales=self.locales,
                        catalogs=self.catalogs,
                        tokens=self.tokens,
                    )
                )
                self.generated_markers["runtime"] += 1
            elif text_key == "__template__":
                assert template_key is not None
                message = self.messages[template_key]
                if not isinstance(message, str):
                    raise SiteBuildError(f"template message {template_key} must be plain text")
                self.output.append(
                    html.escape(
                        expand_tokens(message, self.tokens, key=template_key), quote=False
                    )
                )
                self.used_message_keys.add(template_key)
            elif text_key:
                if text_key not in self.messages:
                    raise SiteBuildError(f"missing message {text_key} for {self.locale['code']}")
                if tag in {"title", "textarea"}:
                    message = self.messages[text_key]
                    if not isinstance(message, str):
                        raise SiteBuildError(
                            f"plain-text element <{tag}> cannot render rich message {text_key}"
                        )
                    self.output.append(
                        html.escape(expand_tokens(message, self.tokens, key=text_key), quote=False)
                    )
                else:
                    self.output.append(
                        render_plain_message(
                            self.messages[text_key],
                            self.tokens,
                            self.markup_tokens,
                            key=text_key,
                        )
                    )
                self.used_message_keys.add(text_key)
            else:
                assert rich_key is not None
                if rich_key not in self.messages:
                    raise SiteBuildError(f"missing rich message {rich_key} for {self.locale['code']}")
                self.output.append(
                    render_rich_message(
                        self.messages[rich_key],
                        self.tokens,
                        self.markup_tokens,
                        self.links,
                        self.messages,
                        self.used_message_keys,
                        key=rich_key,
                        path_prefix=self.path_prefix,
                    )
                )
                self.used_message_keys.add(rich_key)
            self.replacement_tag = tag
            self.suppressed_depth = 0

        for language_attribute in LANGUAGE_BEARING_ATTRIBUTES:
            original = attrs_dict.get(language_attribute)
            if original and language_attribute not in attribute_markers and not self.invariant_text(original):
                raise SiteBuildError(
                    f"unlocalized {language_attribute} on <{tag}>: {original!r}"
                )

        if tag == "meta" and attrs_dict.get("name") == "description":
            if "content" not in attribute_markers:
                raise SiteBuildError("meta description must use data-i18n-attrs")

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag: str) -> None:
        tag = tag.lower()
        if self.replacement_tag is not None:
            if self.suppressed_depth:
                self.suppressed_depth -= 1
                return
            if tag != self.replacement_tag:
                raise SiteBuildError(
                    f"translation replacement for <{self.replacement_tag}> closed by <{tag}>"
                )
            self.output.append(f"</{tag}>")
            self.replacement_tag = None
            if self.open_elements:
                self.open_elements.pop()
            return

        self.output.append(f"</{tag}>")
        if self.open_elements:
            self.open_elements.pop()

    def handle_data(self, data: str) -> None:
        if self.replacement_tag is not None:
            return
        if not any(tag in IGNORED_TEXT_ELEMENTS for tag in self.open_elements):
            normalized = " ".join(data.split())
            if normalized and not self.invariant_text(normalized):
                raise SiteBuildError(f"unlocalized visible text: {normalized!r}")
        self.output.append(data)

    def handle_entityref(self, name: str) -> None:
        if self.replacement_tag is None:
            self.output.append(f"&{name};")

    def handle_charref(self, name: str) -> None:
        if self.replacement_tag is None:
            self.output.append(f"&#{name};")

    def handle_pi(self, data: str) -> None:
        if self.replacement_tag is None:
            self.output.append(f"<?{data}>")

    def unknown_decl(self, data: str) -> None:
        if self.replacement_tag is None:
            self.output.append(f"<![{data}]>")


def validate_locale_manifest(raw: Any) -> tuple[str, list[dict[str, Any]]]:
    if not isinstance(raw, dict) or set(raw) != {"default", "locales"}:
        raise SiteBuildError("locales.json must contain exactly default and locales")
    default = raw["default"]
    locales = raw["locales"]
    if default != "en" or not isinstance(locales, list):
        raise SiteBuildError("default locale must be en and locales must be a list")

    seen_codes: set[str] = set()
    seen_paths: set[str] = set()
    result: list[dict[str, Any]] = []
    required_fields = {"code", "path", "dir", "ogLocale", "nativeName", "browserMatches"}
    for locale in locales:
        if not isinstance(locale, dict) or not required_fields.issubset(locale):
            raise SiteBuildError(f"invalid locale registry entry: {locale!r}")
        unknown = set(locale) - required_fields
        if unknown:
            raise SiteBuildError(f"unknown locale registry fields: {sorted(unknown)}")
        code = locale["code"]
        path = locale["path"].strip("/") if isinstance(locale["path"], str) else None
        direction = locale["dir"]
        open_graph_locale = locale["ogLocale"]
        native_name = locale["nativeName"]
        browser_matches = locale["browserMatches"]
        if code not in EXPECTED_LOCALE_ROUTES or path != EXPECTED_LOCALE_ROUTES.get(code):
            raise SiteBuildError(f"locale route does not match product spec: {code!r} -> {path!r}")
        if direction not in {"ltr", "rtl"} or (code == "ar") != (direction == "rtl"):
            raise SiteBuildError(f"invalid direction for locale {code}")
        if not isinstance(open_graph_locale, str) or not re.fullmatch(
            r"[a-z]{2}_[A-Z]{2}", open_graph_locale
        ):
            raise SiteBuildError(f"locale {code} has no valid Open Graph locale")
        if not isinstance(native_name, str) or not native_name.strip():
            raise SiteBuildError(f"locale {code} has no native name")
        if not isinstance(browser_matches, list) or not browser_matches or not all(
            isinstance(value, str) and value for value in browser_matches
        ):
            raise SiteBuildError(f"locale {code} has invalid browser matches")
        normalized_matches = [value.lower() for value in browser_matches]
        if len(set(normalized_matches)) != len(normalized_matches):
            raise SiteBuildError(f"locale {code} repeats browser matches")
        if code in seen_codes or path in seen_paths:
            raise SiteBuildError(f"duplicate locale registry entry: {code!r} / {path!r}")
        seen_codes.add(code)
        seen_paths.add(path)
        normalized = dict(locale)
        normalized["path"] = path
        normalized["browserMatches"] = normalized_matches
        result.append(normalized)

    if seen_codes != set(EXPECTED_LOCALE_ROUTES):
        raise SiteBuildError(
            f"locale registry differs from product spec: {sorted(seen_codes)}"
        )
    if result[0]["code"] != "en":
        raise SiteBuildError("English must be the first locale registry entry")
    return default, result


def validate_catalogs(
    *,
    source_dir: Path,
    locales: Sequence[Mapping[str, Any]],
    tokens: Mapping[str, str],
    links: Mapping[str, Any],
) -> dict[str, dict[str, Any]]:
    catalogs: dict[str, dict[str, Any]] = {}
    for locale in locales:
        path = source_dir / "i18n" / f"{locale['code']}.json"
        raw_catalog = load_json(path)
        if not isinstance(raw_catalog, dict) or raw_catalog.get("locale") != locale["code"]:
            raise SiteBuildError(f"locale catalog identity mismatch: {path}")
        raw_messages = {key: value for key, value in raw_catalog.items() if key != "locale"}
        catalogs[locale["code"]] = flatten_messages(raw_messages)

    english = catalogs["en"]
    if not english:
        raise SiteBuildError("English locale catalog is empty")
    expected_keys = set(english)
    for key, value in english.items():
        if not any(text.strip() for text in message_texts(value)):
            raise SiteBuildError(f"English message {key} is empty")
        if any("<" in text or ">" in text for text in message_texts(value)):
            raise SiteBuildError(f"English message {key} contains raw HTML")
        allowed_tokens = set(tokens)
        unknown_tokens = set(placeholder_counter(value)) - allowed_tokens
        if unknown_tokens:
            raise SiteBuildError(
                f"English message {key} uses unknown tokens: {sorted(unknown_tokens)}"
            )
        validate_rich_shape(key, value, value, links)

    for code, catalog in catalogs.items():
        if set(catalog) != expected_keys:
            missing = sorted(expected_keys - set(catalog))
            extra = sorted(set(catalog) - expected_keys)
            raise SiteBuildError(f"locale {code} key mismatch; missing={missing}, extra={extra}")
        for key, value in catalog.items():
            if not any(text.strip() for text in message_texts(value)):
                raise SiteBuildError(f"locale {code} message {key} is empty")
            if any("<" in text or ">" in text for text in message_texts(value)):
                raise SiteBuildError(f"locale {code} message {key} contains raw HTML")
            validate_rich_shape(key, english[key], value, links)
            if placeholder_counter(value) != placeholder_counter(english[key]):
                raise SiteBuildError(f"locale {code} placeholders differ from English for {key}")

    required_runtime_keys = set(RUNTIME_MESSAGE_KEYS) | set(SUGGESTION_MESSAGE_KEYS)
    missing_runtime = sorted(required_runtime_keys - expected_keys)
    if missing_runtime:
        raise SiteBuildError(f"English catalog is missing runtime keys: {missing_runtime}")
    for code, catalog in catalogs.items():
        for key in required_runtime_keys:
            if not isinstance(catalog[key], str):
                raise SiteBuildError(f"runtime message {key} must be plain text in {code}")
    return catalogs


def reject_symlinks(path: Path) -> None:
    if path.is_symlink():
        raise SiteBuildError(f"public site source must not be a symlink: {path}")
    if path.is_dir():
        for descendant in path.rglob("*"):
            if descendant.is_symlink():
                raise SiteBuildError(
                    f"public site source must not contain symlinks: {descendant}"
                )


def render_locale_page(
    *,
    source_html: str,
    locale: Mapping[str, Any],
    locales: Sequence[Mapping[str, Any]],
    catalogs: Mapping[str, Mapping[str, Any]],
    tokens: Mapping[str, str],
    markup_tokens: Mapping[str, str],
    links: Mapping[str, Any],
    commands: Mapping[str, str],
    videos: Mapping[str, Any],
) -> str:
    parser = LocalizedHTMLParser(
        locale=locale,
        locales=locales,
        messages=catalogs[locale["code"]],
        catalogs=catalogs,
        tokens=tokens,
        markup_tokens=markup_tokens,
        links=links,
        commands=commands,
        videos=videos,
    )
    try:
        parser.feed(source_html)
        parser.close()
    except (AssertionError, ValueError) as error:
        raise SiteBuildError(f"could not parse landing HTML: {error}") from error
    if parser.replacement_tag is not None:
        raise SiteBuildError(f"unclosed localized element <{parser.replacement_tag}>")
    expected_markers = Counter({"languageLinks": 1, "runtime": 1})
    for locale in locales:
        expected_markers[f"alternate:{locale['code']}"] = 1
    expected_markers["alternate:x-default"] = 1
    if parser.generated_markers != expected_markers:
        raise SiteBuildError(
            f"generated HTML markers differ from expected: {parser.generated_markers}"
        )

    catalog_keys = set(catalogs[locale["code"]])
    runtime_only = set(RUNTIME_MESSAGE_KEYS) | set(SUGGESTION_MESSAGE_KEYS)
    unused = sorted(catalog_keys - parser.used_message_keys - runtime_only)
    if unused:
        raise SiteBuildError(f"locale catalog has unused page messages: {unused}")
    return "".join(parser.output)


def write_sitemap(output_dir: Path, locales: Sequence[Mapping[str, Any]]) -> None:
    alternates = [*locales, {"code": "x-default", "path": ""}]
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"',
        '        xmlns:xhtml="http://www.w3.org/1999/xhtml">',
    ]
    for locale in locales:
        lines.append("  <url>")
        lines.append(f"    <loc>{html.escape(locale_url(locale['path']))}</loc>")
        for alternate in alternates:
            lines.append(
                "    <xhtml:link rel=\"alternate\" "
                f"hreflang=\"{html.escape(alternate['code'], quote=True)}\" "
                f"href=\"{html.escape(locale_url(alternate['path']), quote=True)}\" />"
            )
        lines.append("  </url>")
    lines.append("</urlset>")
    (output_dir / "sitemap.xml").write_text("\n".join(lines) + "\n", encoding="utf-8")


def build_site(*, source_dir: Path, output_dir: Path) -> list[Path]:
    source_dir = source_dir.resolve()
    output_dir = output_dir.resolve()
    if output_dir == source_dir or source_dir in output_dir.parents and output_dir.name != "public":
        raise SiteBuildError(f"unsafe output directory: {output_dir}")
    if output_dir.exists():
        if not output_dir.is_dir():
            raise SiteBuildError(f"output path is not a directory: {output_dir}")
        if any(output_dir.iterdir()):
            raise SiteBuildError(f"output directory must be empty: {output_dir}")

    required_sources = (
        source_dir / "index.html",
        source_dir / "styles.css",
        source_dir / "script.js",
        source_dir / "assets",
        source_dir / "assets" / SOCIAL_PREVIEW_FILENAME,
        source_dir / "i18n" / "site.json",
        source_dir / "i18n" / "locales.json",
    )
    for source in required_sources:
        if not source.exists():
            raise SiteBuildError(f"required website source not found: {source}")
        reject_symlinks(source)

    social_preview_source = source_dir / "assets" / SOCIAL_PREVIEW_FILENAME
    social_preview_dimensions = read_png_dimensions(social_preview_source)
    if social_preview_dimensions != SOCIAL_PREVIEW_DIMENSIONS:
        expected_width, expected_height = SOCIAL_PREVIEW_DIMENSIONS
        actual_width, actual_height = social_preview_dimensions
        raise SiteBuildError(
            "social preview must be "
            f"{expected_width}x{expected_height}, got {actual_width}x{actual_height}: "
            f"{social_preview_source}"
        )

    site = load_json(source_dir / "i18n" / "site.json")
    if not isinstance(site, dict) or not isinstance(site.get("tokens"), dict) or not isinstance(
        site.get("links"), dict
    ):
        raise SiteBuildError("site.json must contain token and link objects")
    token_records = site["tokens"]
    links = site["links"]
    commands = site.get("commands")
    videos = site.get("video")
    if not isinstance(commands, dict) or not all(
        isinstance(key, str) and isinstance(value, str) for key, value in commands.items()
    ):
        raise SiteBuildError("site commands must be string pairs")
    if not isinstance(videos, dict):
        raise SiteBuildError("site video registry must be an object")
    if not all(isinstance(key, str) and isinstance(value, dict) for key, value in token_records.items()):
        raise SiteBuildError("site tokens must be named objects")
    tokens: dict[str, str] = {}
    token_directions: dict[str, str] = {}
    token_languages: dict[str, str | None] = {}
    for key, record in token_records.items():
        value = record.get("value")
        if not isinstance(value, str) or not value:
            raise SiteBuildError(f"site token {key!r} has no string value")
        direction = record.get("direction")
        if direction not in {"ltr", "rtl"}:
            raise SiteBuildError(f"site token {key!r} has no valid text direction")
        language = record.get("language")
        if language is not None and (
            not isinstance(language, str)
            or not re.fullmatch(r"[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*", language)
        ):
            raise SiteBuildError(f"site token {key!r} has no valid language")
        tokens[key] = value
        token_directions[key] = direction
        token_languages[key] = language

    default, locales = validate_locale_manifest(load_json(source_dir / "i18n" / "locales.json"))
    if default != "en":
        raise SiteBuildError("unsupported default locale")
    catalogs = validate_catalogs(
        source_dir=source_dir,
        locales=locales,
        tokens=tokens,
        links=links,
    )

    source_html = (source_dir / "index.html").read_text(encoding="utf-8")
    output_dir.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    for locale in locales:
        page_tokens = {
            key: f"\u2066{value}\u2069"
            if locale["dir"] == "rtl" and token_directions[key] == "ltr"
            else value
            for key, value in tokens.items()
        }
        page_markup_tokens: dict[str, str] = {}
        for key, value in tokens.items():
            attributes: list[str] = []
            language = token_languages[key]
            if language and not locale["code"].lower().startswith(language.lower()):
                attributes.append(f' lang="{html.escape(language, quote=True)}"')
            if language or token_directions[key] != locale["dir"]:
                attributes.append(f' dir="{token_directions[key]}"')
            escaped_value = html.escape(value, quote=False)
            page_markup_tokens[key] = (
                f"<bdi{''.join(attributes)}>{escaped_value}</bdi>"
                if attributes
                else escaped_value
            )
        page = render_locale_page(
            source_html=source_html,
            locale=locale,
            locales=locales,
            catalogs=catalogs,
            tokens=page_tokens,
            markup_tokens=page_markup_tokens,
            links=links,
            commands=commands,
            videos=videos,
        )
        destination_dir = output_dir / locale["path"] if locale["path"] else output_dir
        destination_dir.mkdir(parents=True, exist_ok=True)
        destination = destination_dir / "index.html"
        destination.write_text(page, encoding="utf-8")
        written.append(destination)

    for filename in ("styles.css", "script.js"):
        destination = output_dir / filename
        shutil.copy2(source_dir / filename, destination)
        written.append(destination)
    assets_destination = output_dir / "assets"
    shutil.copytree(source_dir / "assets", assets_destination)
    written.extend(path for path in assets_destination.rglob("*") if path.is_file())

    write_sitemap(output_dir, locales)
    written.append(output_dir / "sitemap.xml")
    robots = "User-agent: *\nAllow: /\nSitemap: https://holdtype.app/sitemap.xml\n"
    (output_dir / "robots.txt").write_text(robots, encoding="utf-8")
    written.append(output_dir / "robots.txt")
    return sorted(written)


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument(
        "--source-dir",
        type=Path,
        default=Path(__file__).resolve().parent,
        help="website source directory (defaults to the directory containing this script)",
    )
    result.add_argument("--output-dir", type=Path, required=True)
    return result


def main(argv: Sequence[str] | None = None) -> int:
    args = parser().parse_args(argv)
    written = build_site(source_dir=args.source_dir, output_dir=args.output_dir)
    print(f"Built {len(written)} public files for {len(EXPECTED_LOCALE_ROUTES)} locales.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SiteBuildError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
