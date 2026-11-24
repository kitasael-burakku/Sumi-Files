#!/usr/bin/env python3
"""
vscodium-theme.py — makes VSCodium follow the Minimaru palette.

Sources (both are written by matugen AND by apply-static-colors.sh, so dynamic
and static modes are covered without touching either pipeline):
  ~/.local/state/sumi-shell/colors.json   Material roles  -> workbench UI
  ~/.config/kitty/colors/colors.conf      ANSI palette    -> syntax + terminal
                                          (the same file Neovim's minimaru reads)

Output: themes/minimaru-{dark,light}.json inside the locally installed
"minimaru.minimaru-theme" extension. Its package.json declares `"_watch": true`
for both themes, which makes VSCodium re-read the active theme file whenever it
changes: recoloring is live, no window reload. Both files receive the current
palette; they differ only in the base (uiTheme) VSCodium uses for anything the
theme does not set, so whichever one window.autoDetectColorScheme picks shows
the right colors.

Triggered by vscodium-theme.path (systemd --user) when colors.json changes.

Usage:
  vscodium-theme.py            regenerate the installed theme (no-op if absent)
  vscodium-theme.py --install  build the extension as a .vsix and install it
"""

import json
import os
import re
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path

HOME = Path.home()
STATE = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state"))
SHELL_COLORS = STATE / "sumi-shell/colors.json"
KITTY_COLORS = HOME / ".config/kitty/colors/colors.conf"
EXT_ROOT = HOME / ".vscode-oss/extensions"
EXT_GLOB = "minimaru.minimaru-theme-*"

VERSION = "1.0.0"
PACKAGE_JSON = {
    "name": "minimaru-theme",
    "displayName": "Minimaru",
    "description": "Follows the Minimaru session palette (matugen / static), live.",
    "publisher": "minimaru",
    "version": VERSION,
    "engines": {"vscode": "^1.80.0"},
    "categories": ["Themes"],
    "contributes": {
        "themes": [
            {"label": "Minimaru Dark", "uiTheme": "vs-dark",
             "path": "./themes/minimaru-dark.json", "_watch": True},
            {"label": "Minimaru Light", "uiTheme": "vs",
             "path": "./themes/minimaru-light.json", "_watch": True},
        ]
    },
}

HEX = re.compile(r"^#[0-9a-fA-F]{6}$")


# ── palette loading ──────────────────────────────────────────────────────────

def wait_settled(paths, quiet=0.3, limit=5.0):
    """matugen/cp write in bursts: wait until no source changed for `quiet` s."""
    deadline = time.monotonic() + limit
    last = None
    while time.monotonic() < deadline:
        now = tuple(p.stat().st_mtime_ns if p.exists() else 0 for p in paths)
        if now == last:
            return
        last = now
        time.sleep(quiet)


def load_material():
    data = json.loads(SHELL_COLORS.read_text())
    return {k: v.lower() for k, v in data.items() if isinstance(v, str) and HEX.match(v)}


def load_kitty():
    out = {}
    for line in KITTY_COLORS.read_text().splitlines():
        parts = line.split()
        if len(parts) >= 2 and HEX.match(parts[1]):
            out[parts[0]] = parts[1].lower()
    return out


# ── color helpers ────────────────────────────────────────────────────────────

def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def a(h, alpha):
    """Append an alpha byte (0-255) to #rrggbb."""
    return f"{h}{alpha:02x}"


def mix(h1, h2, t):
    """Blend h1 toward h2 by t (0..1)."""
    c1, c2 = rgb(h1), rgb(h2)
    return "#" + "".join(f"{round(x + (y - x) * t):02x}" for x, y in zip(c1, c2))


def is_dark(h):
    r, g, b = rgb(h)
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 < 0.5


# ── theme ────────────────────────────────────────────────────────────────────

def build_theme(name, ui_dark, m, k):
    def role(key, fallback):
        return m.get(key) or fallback

    bg = role("surface", k.get("background", "#131313"))
    fg = role("on_surface", k.get("foreground", "#e5e2e1"))
    dark = is_dark(bg)
    lowest = role("surface_container_lowest", bg)
    low = role("surface_container_low", bg)
    mid = role("surface_container", bg)
    high = role("surface_container_high", bg)
    fg2 = role("on_surface_variant", fg)
    outline = role("outline", fg2)
    primary = role("primary", k.get("color4", fg))
    on_primary = role("on_primary", bg)
    secondary = role("secondary", primary)
    tertiary = role("tertiary", primary)
    error = role("error", k.get("color1", "#ff5555"))
    primary_fixed = role("primary_fixed", primary)
    shadow = "#00000059" if dark else "#00000024"
    hover = mix(high, fg, 0.06)

    c = {i: k.get(f"color{i}", fg) for i in range(16)}

    colors = {
        # base
        "foreground": fg,
        "descriptionForeground": fg2,
        "disabledForeground": a(fg2, 0x80),
        "errorForeground": error,
        "icon.foreground": fg2,
        "focusBorder": a(primary, 0x80),
        "contrastBorder": "#00000000",
        "selection.background": a(primary, 0x50),
        "widget.shadow": shadow,
        "widget.border": high,
        "sash.hoverBorder": a(primary, 0x80),
        "textLink.foreground": primary,
        "textLink.activeForeground": primary_fixed,
        "textPreformat.foreground": tertiary,
        "textPreformat.background": mid,
        "textBlockQuote.background": low,
        "textBlockQuote.border": outline,
        "textCodeBlock.background": low,
        "textSeparator.foreground": outline,
        "toolbar.hoverBackground": high,
        "progressBar.background": primary,
        # buttons, badges, inputs
        "button.background": primary,
        "button.foreground": on_primary,
        "button.hoverBackground": mix(primary, fg if dark else bg, 0.15),
        "button.secondaryBackground": high,
        "button.secondaryForeground": fg,
        "button.secondaryHoverBackground": hover,
        "badge.background": primary,
        "badge.foreground": on_primary,
        "input.background": mid,
        "input.border": high,
        "input.foreground": fg,
        "input.placeholderForeground": a(fg2, 0x99),
        "inputOption.activeBorder": primary,
        "inputOption.activeBackground": a(primary, 0x30),
        "inputOption.activeForeground": fg,
        "inputValidation.errorBackground": mid,
        "inputValidation.errorBorder": error,
        "inputValidation.warningBackground": mid,
        "inputValidation.warningBorder": tertiary,
        "inputValidation.infoBackground": mid,
        "inputValidation.infoBorder": primary,
        "dropdown.background": mid,
        "dropdown.listBackground": mid,
        "dropdown.border": high,
        "dropdown.foreground": fg,
        "checkbox.background": mid,
        "checkbox.border": outline,
        "checkbox.foreground": fg,
        "keybindingLabel.background": high,
        "keybindingLabel.foreground": fg,
        "keybindingLabel.border": high,
        "keybindingLabel.bottomBorder": outline,
        "scrollbar.shadow": "#00000000",
        "scrollbarSlider.background": a(outline, 0x30),
        "scrollbarSlider.hoverBackground": a(outline, 0x50),
        "scrollbarSlider.activeBackground": a(outline, 0x70),
        # lists / trees
        "list.activeSelectionBackground": a(primary, 0x30),
        "list.activeSelectionForeground": fg,
        "list.activeSelectionIconForeground": fg,
        "list.inactiveSelectionBackground": high,
        "list.inactiveSelectionForeground": fg,
        "list.hoverBackground": a(high, 0xb0),
        "list.hoverForeground": fg,
        "list.focusOutline": a(primary, 0x80),
        "list.inactiveFocusOutline": "#00000000",
        "list.highlightForeground": primary,
        "list.focusHighlightForeground": primary,
        "list.errorForeground": error,
        "list.warningForeground": tertiary,
        "list.dropBackground": a(primary, 0x20),
        "tree.indentGuidesStroke": high,
        "tree.inactiveIndentGuidesStroke": a(high, 0x80),
        # chrome: title, activity, side bar, status
        "titleBar.activeBackground": low,
        "titleBar.activeForeground": fg,
        "titleBar.inactiveBackground": low,
        "titleBar.inactiveForeground": outline,
        "titleBar.border": low,
        "commandCenter.background": mid,
        "commandCenter.foreground": fg2,
        "commandCenter.activeBackground": high,
        "commandCenter.activeForeground": fg,
        "commandCenter.border": high,
        "commandCenter.inactiveBorder": mid,
        "menubar.selectionBackground": high,
        "menubar.selectionForeground": fg,
        "menu.background": mid,
        "menu.foreground": fg,
        "menu.border": high,
        "menu.selectionBackground": a(primary, 0x30),
        "menu.selectionForeground": fg,
        "menu.separatorBackground": high,
        "activityBar.background": low,
        "activityBar.foreground": fg,
        "activityBar.inactiveForeground": outline,
        "activityBar.activeBorder": primary,
        "activityBar.border": low,
        "activityBarBadge.background": primary,
        "activityBarBadge.foreground": on_primary,
        "activityBarTop.foreground": fg,
        "activityBarTop.inactiveForeground": outline,
        "activityBarTop.activeBorder": primary,
        "sideBar.background": low,
        "sideBar.foreground": fg2,
        "sideBar.border": low,
        "sideBarTitle.foreground": fg,
        "sideBarSectionHeader.background": low,
        "sideBarSectionHeader.foreground": fg,
        "sideBarSectionHeader.border": mid,
        "statusBar.background": low,
        "statusBar.foreground": fg2,
        "statusBar.border": low,
        "statusBar.noFolderBackground": low,
        "statusBar.debuggingBackground": tertiary,
        "statusBar.debuggingForeground": bg,
        "statusBarItem.hoverBackground": high,
        "statusBarItem.remoteBackground": primary,
        "statusBarItem.remoteForeground": on_primary,
        # editor groups and tabs
        "editorGroup.border": high,
        "editorGroup.dropBackground": a(primary, 0x20),
        "editorGroupHeader.tabsBackground": low,
        "editorGroupHeader.tabsBorder": low,
        "editorGroupHeader.noTabsBackground": bg,
        "tab.activeBackground": bg,
        "tab.activeForeground": fg,
        "tab.activeBorderTop": primary,
        "tab.activeModifiedBorder": tertiary,
        "tab.inactiveBackground": low,
        "tab.inactiveForeground": outline,
        "tab.inactiveModifiedBorder": a(tertiary, 0x80),
        "tab.hoverBackground": mid,
        "tab.hoverForeground": fg,
        "tab.border": low,
        "tab.lastPinnedBorder": high,
        "tab.unfocusedActiveForeground": fg2,
        "tab.unfocusedActiveBorderTop": a(primary, 0x60),
        "breadcrumb.background": bg,
        "breadcrumb.foreground": outline,
        "breadcrumb.focusForeground": fg,
        "breadcrumb.activeSelectionForeground": primary,
        "breadcrumbPicker.background": mid,
        # panel, terminal
        "panel.background": bg,
        "panel.border": high,
        "panelTitle.activeForeground": fg,
        "panelTitle.inactiveForeground": outline,
        "panelTitle.activeBorder": primary,
        "panelSectionHeader.background": low,
        "terminal.background": bg,
        "terminal.foreground": k.get("foreground", fg),
        "terminalCursor.foreground": k.get("cursor", fg),
        "terminal.selectionBackground": k.get("selection_background", high),
        "terminal.ansiBlack": c[0], "terminal.ansiBrightBlack": c[8],
        "terminal.ansiRed": c[1], "terminal.ansiBrightRed": c[9],
        "terminal.ansiGreen": c[2], "terminal.ansiBrightGreen": c[10],
        "terminal.ansiYellow": c[3], "terminal.ansiBrightYellow": c[11],
        "terminal.ansiBlue": c[4], "terminal.ansiBrightBlue": c[12],
        "terminal.ansiMagenta": c[5], "terminal.ansiBrightMagenta": c[13],
        "terminal.ansiCyan": c[6], "terminal.ansiBrightCyan": c[14],
        "terminal.ansiWhite": c[7], "terminal.ansiBrightWhite": c[15],
        # editor
        "editor.background": bg,
        "editor.foreground": fg,
        "editorCursor.foreground": primary,
        "editor.lineHighlightBackground": a(high, 0x70),
        "editor.lineHighlightBorder": "#00000000",
        "editorLineNumber.foreground": a(outline, 0xa0),
        "editorLineNumber.activeForeground": fg,
        "editor.selectionBackground": a(primary, 0x40),
        "editor.inactiveSelectionBackground": a(primary, 0x20),
        "editor.selectionHighlightBackground": a(primary, 0x25),
        "editor.wordHighlightBackground": a(primary, 0x20),
        "editor.wordHighlightStrongBackground": a(primary, 0x30),
        "editor.findMatchBackground": a(tertiary, 0x60),
        "editor.findMatchHighlightBackground": a(tertiary, 0x30),
        "editor.findRangeHighlightBackground": a(high, 0x80),
        "editor.rangeHighlightBackground": a(high, 0x60),
        "editor.foldBackground": a(high, 0x50),
        "editorLink.activeForeground": primary,
        "editorWhitespace.foreground": a(outline, 0x50),
        "editorIndentGuide.background1": high,
        "editorIndentGuide.activeBackground1": a(outline, 0x90),
        "editorRuler.foreground": high,
        "editorCodeLens.foreground": outline,
        "editorInlayHint.foreground": outline,
        "editorInlayHint.background": a(high, 0x60),
        "editorBracketMatch.background": a(primary, 0x25),
        "editorBracketMatch.border": a(primary, 0x80),
        "editorBracketHighlight.foreground1": c[4],
        "editorBracketHighlight.foreground2": c[5],
        "editorBracketHighlight.foreground3": c[14],
        "editorBracketHighlight.foreground4": c[3],
        "editorBracketHighlight.foreground5": c[2],
        "editorBracketHighlight.foreground6": c[13],
        "editorBracketHighlight.unexpectedBracket.foreground": error,
        "editorGutter.background": bg,
        "editorGutter.addedBackground": c[2],
        "editorGutter.modifiedBackground": c[4],
        "editorGutter.deletedBackground": c[1],
        "editorError.foreground": error,
        "editorWarning.foreground": tertiary,
        "editorInfo.foreground": primary,
        "editorHint.foreground": secondary,
        "editorOverviewRuler.border": "#00000000",
        "editorOverviewRuler.errorForeground": error,
        "editorOverviewRuler.warningForeground": tertiary,
        "editorOverviewRuler.infoForeground": primary,
        "editorOverviewRuler.findMatchForeground": a(tertiary, 0xa0),
        "editorOverviewRuler.selectionHighlightForeground": a(primary, 0x80),
        "editorOverviewRuler.addedForeground": a(c[2], 0xa0),
        "editorOverviewRuler.modifiedForeground": a(c[4], 0xa0),
        "editorOverviewRuler.deletedForeground": a(c[1], 0xa0),
        "editorStickyScroll.background": bg,
        "editorStickyScrollHover.background": mid,
        "editorStickyScroll.shadow": shadow,
        "minimap.background": bg,
        "minimap.selectionHighlight": a(primary, 0x60),
        "minimap.findMatchHighlight": a(tertiary, 0x80),
        "minimap.errorHighlight": a(error, 0xa0),
        "minimap.warningHighlight": a(tertiary, 0xa0),
        "minimapSlider.background": a(outline, 0x20),
        "minimapSlider.hoverBackground": a(outline, 0x35),
        "minimapSlider.activeBackground": a(outline, 0x50),
        "minimapGutter.addedBackground": c[2],
        "minimapGutter.modifiedBackground": c[4],
        "minimapGutter.deletedBackground": c[1],
        # widgets, pickers, peek, notifications
        "editorWidget.background": mid,
        "editorWidget.foreground": fg,
        "editorWidget.border": high,
        "editorSuggestWidget.background": mid,
        "editorSuggestWidget.border": high,
        "editorSuggestWidget.foreground": fg,
        "editorSuggestWidget.selectedBackground": a(primary, 0x30),
        "editorSuggestWidget.selectedForeground": fg,
        "editorSuggestWidget.highlightForeground": primary,
        "editorSuggestWidget.focusHighlightForeground": primary,
        "editorHoverWidget.background": mid,
        "editorHoverWidget.border": high,
        "editorHoverWidget.statusBarBackground": high,
        "quickInput.background": mid,
        "quickInput.foreground": fg,
        "quickInputTitle.background": high,
        "quickInputList.focusBackground": a(primary, 0x30),
        "quickInputList.focusForeground": fg,
        "pickerGroup.foreground": primary,
        "pickerGroup.border": high,
        "peekView.border": primary,
        "peekViewEditor.background": low,
        "peekViewEditorGutter.background": low,
        "peekViewEditor.matchHighlightBackground": a(tertiary, 0x40),
        "peekViewResult.background": mid,
        "peekViewResult.selectionBackground": a(primary, 0x30),
        "peekViewResult.matchHighlightBackground": a(tertiary, 0x40),
        "peekViewTitle.background": mid,
        "peekViewTitleLabel.foreground": fg,
        "peekViewTitleDescription.foreground": fg2,
        "notifications.background": mid,
        "notifications.foreground": fg,
        "notifications.border": high,
        "notificationCenterHeader.background": high,
        "notificationCenterHeader.foreground": fg,
        "notificationToast.border": high,
        "notificationsErrorIcon.foreground": error,
        "notificationsWarningIcon.foreground": tertiary,
        "notificationsInfoIcon.foreground": primary,
        "debugToolBar.background": mid,
        "settings.headerForeground": fg,
        "settings.modifiedItemIndicator": primary,
        "settings.focusedRowBackground": a(high, 0x50),
        "settings.rowHoverBackground": a(high, 0x30),
        "welcomePage.tileBackground": low,
        "welcomePage.tileHoverBackground": mid,
        "walkThrough.embeddedEditorBackground": low,
        # diff and git
        "diffEditor.insertedTextBackground": a(c[2], 0x26),
        "diffEditor.removedTextBackground": a(c[1], 0x26),
        "diffEditor.insertedLineBackground": a(c[2], 0x12),
        "diffEditor.removedLineBackground": a(c[1], 0x12),
        "diffEditor.diagonalFill": a(high, 0x80),
        "gitDecoration.addedResourceForeground": c[2],
        "gitDecoration.modifiedResourceForeground": c[4],
        "gitDecoration.deletedResourceForeground": c[1],
        "gitDecoration.renamedResourceForeground": c[14],
        "gitDecoration.untrackedResourceForeground": c[10],
        "gitDecoration.ignoredResourceForeground": outline,
        "gitDecoration.conflictingResourceForeground": tertiary,
        "gitDecoration.submoduleResourceForeground": secondary,
        # Error Lens (installed extension)
        "errorLens.errorBackground": a(error, 0x14),
        "errorLens.errorForeground": error,
        "errorLens.warningBackground": a(tertiary, 0x14),
        "errorLens.warningForeground": tertiary,
        "errorLens.infoBackground": a(primary, 0x14),
        "errorLens.infoForeground": primary,
        "errorLens.hintBackground": a(secondary, 0x10),
        "errorLens.hintForeground": secondary,
    }

    def rule(scope, color, style=None):
        settings = {"foreground": color}
        if style:
            settings["fontStyle"] = style
        return {"scope": scope, "settings": settings}

    # Syntax: same ANSI slots Neovim's minimaru maps onto tokyonight.
    tokens = [
        rule(["comment", "punctuation.definition.comment", "string.comment"], c[8], "italic"),
        rule(["keyword", "storage.type", "storage.modifier", "keyword.control",
              "keyword.other", "keyword.declaration"], c[5]),
        rule(["keyword.operator", "punctuation", "meta.brace", "punctuation.separator",
              "punctuation.terminator", "punctuation.accessor"], c[7]),
        rule(["keyword.operator.new", "keyword.operator.expression",
              "keyword.operator.logical.python", "keyword.operator.word"], c[5]),
        rule(["string", "punctuation.definition.string", "markup.inline.raw"], c[2]),
        rule(["string.regexp", "constant.character.escape", "constant.other.placeholder",
              "string.interpolated punctuation"], c[14]),
        rule(["constant.numeric", "constant.language", "constant.other",
              "constant.character", "variable.other.constant", "variable.other.enummember"], c[3]),
        rule(["entity.name.function", "support.function", "meta.function-call.generic",
              "variable.function", "entity.name.method"], c[4]),
        rule(["entity.name.type", "entity.name.class", "entity.name.namespace",
              "support.type", "support.class", "entity.other.inherited-class",
              "storage.type.class", "entity.name.type.module"], c[14]),
        rule(["variable", "meta.definition.variable", "variable.other.readwrite",
              "variable.other.property", "variable.other.object.property",
              "support.variable.property", "meta.object-literal.key"], fg),
        rule(["variable.parameter", "meta.parameter"], fg, "italic"),
        rule(["variable.language", "variable.parameter.function.language.special.self.python",
              "variable.language.this"], c[1], "italic"),
        rule(["support.function.builtin", "support.type.builtin", "support.constant",
              "meta.decorator", "entity.name.function.decorator",
              "punctuation.definition.decorator", "entity.name.function.preprocessor",
              "meta.preprocessor"], c[13]),
        rule(["entity.name.tag", "meta.tag.sgr", "punctuation.definition.tag"], c[1]),
        rule(["entity.other.attribute-name"], c[3], "italic"),
        rule(["entity.name.section", "markup.heading", "markup.heading entity.name"], c[4], "bold"),
        rule(["markup.bold"], fg, "bold"),
        rule(["markup.italic"], fg, "italic"),
        rule(["markup.underline.link", "string.other.link"], c[14], "underline"),
        rule(["markup.quote"], c[8], "italic"),
        rule(["markup.list punctuation.definition.list"], c[5]),
        rule(["markup.inserted", "meta.diff.header.to-file"], c[2]),
        rule(["markup.deleted", "meta.diff.header.from-file"], c[1]),
        rule(["markup.changed"], c[4]),
        rule(["support.type.property-name.json", "support.type.property-name"], c[4]),
        rule(["invalid", "invalid.illegal"], error),
    ]

    semantic = {
        "namespace": c[14],
        "type": c[14], "class": c[14], "interface": c[14], "struct": c[14],
        "enum": c[14], "typeParameter": c[14],
        "function": c[4], "method": c[4],
        "macro": c[13], "decorator": c[13],
        "keyword": c[5],
        "enumMember": c[3],
        "variable.readonly": c[3],
        "variable.defaultLibrary": c[13],
        "property": fg,
        "parameter": {"foreground": fg, "italic": True},
        "selfParameter": {"foreground": c[1], "italic": True},
        "comment": {"foreground": c[8], "italic": True},
    }

    return {
        "$schema": "vscode://schemas/color-theme",
        "name": name,
        "type": "dark" if ui_dark else "light",
        "semanticHighlighting": True,
        "colors": colors,
        "tokenColors": tokens,
        "semanticTokenColors": semantic,
    }


def render_themes():
    m, k = load_material(), load_kitty()
    return {
        "minimaru-dark.json": build_theme("Minimaru Dark", True, m, k),
        "minimaru-light.json": build_theme("Minimaru Light", False, m, k),
    }


# ── output ───────────────────────────────────────────────────────────────────

def write_if_changed(path, text):
    """Atomic replace, skipped when identical (each write triggers a live reload)."""
    if path.exists() and path.read_text() == text:
        return False
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    with os.fdopen(fd, "w") as fh:
        fh.write(text)
    os.replace(tmp, path)
    return True


def dump(obj):
    return json.dumps(obj, indent=2) + "\n"


def regenerate():
    dirs = sorted(EXT_ROOT.glob(EXT_GLOB))
    if not dirs:
        print("vscodium-theme: extension not installed (run with --install); nothing to do")
        return 0
    wait_settled([SHELL_COLORS, KITTY_COLORS])
    themes = render_themes()
    for d in dirs:
        tdir = d / "themes"
        tdir.mkdir(exist_ok=True)
        changed = [n for n, t in themes.items() if write_if_changed(tdir / n, dump(t))]
        print(f"vscodium-theme: {d.name}: {'updated ' + ', '.join(changed) if changed else 'unchanged'}")
    return 0


VSIX_MANIFEST = f"""<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011" xmlns:d="http://schemas.microsoft.com/developer/vsx-schema-design/2011">
  <Metadata>
    <Identity Language="en-US" Id="minimaru-theme" Version="{VERSION}" Publisher="minimaru"/>
    <DisplayName>Minimaru</DisplayName>
    <Description xml:space="preserve">{PACKAGE_JSON["description"]}</Description>
    <Categories>Themes</Categories>
    <Properties>
      <Property Id="Microsoft.VisualStudio.Code.Engine" Value="{PACKAGE_JSON["engines"]["vscode"]}"/>
      <Property Id="Microsoft.VisualStudio.Code.ExtensionKind" Value="ui"/>
    </Properties>
  </Metadata>
  <Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation>
  <Dependencies/>
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/>
  </Assets>
</PackageManifest>
"""

CONTENT_TYPES = """<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension=".json" ContentType="application/json"/>
  <Default Extension=".vsixmanifest" ContentType="text/xml"/>
</Types>
"""


def install():
    themes = render_themes()
    with tempfile.TemporaryDirectory() as tmp:
        vsix = Path(tmp) / f"minimaru-theme-{VERSION}.vsix"
        with zipfile.ZipFile(vsix, "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("[Content_Types].xml", CONTENT_TYPES)
            z.writestr("extension.vsixmanifest", VSIX_MANIFEST)
            z.writestr("extension/package.json", dump(PACKAGE_JSON))
            for n, t in themes.items():
                z.writestr(f"extension/themes/{n}", dump(t))
        return subprocess.run(["codium", "--install-extension", str(vsix), "--force"]).returncode


def main():
    try:
        return install() if "--install" in sys.argv[1:] else regenerate()
    except (OSError, ValueError) as exc:
        print(f"vscodium-theme: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
