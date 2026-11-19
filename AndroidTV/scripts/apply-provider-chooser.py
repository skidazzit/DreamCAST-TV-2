#!/usr/bin/env python3
"""Apply the DreamCAST Xtream provider chooser to a generated StreamVault tree.

This keeps the upstream submodule unchanged. Existing custom work is never
silently overwritten: anchors are checked and repeated runs are safe.
"""
from pathlib import Path
import argparse
import json

NAMES = ("DreamCAST TV", "Klepto TV", "Strong", "IPTVeditor")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("workspace", type=Path)
    parser.add_argument("--map", dest="mapping", type=Path, default=None,
                        help="Optional local JSON mapping for development; do not publish a mapped APK without review")
    args = parser.parse_args()
    root = args.workspace.expanduser().resolve()
    folder = root / "feature/provider/src/main/java/com/streamvault/feature/provider/setup"
    target = folder / "ProviderSetupSourceForms.kt"
    if not target.exists():
        raise SystemExit(f"Missing StreamVault provider source: {target}")
    assets = root / "feature/provider/src/main/assets"
    assets.mkdir(parents=True, exist_ok=True)
    data = {name: "" for name in NAMES}
    if args.mapping:
        supplied = json.loads(args.mapping.read_text(encoding="utf-8"))
        if not isinstance(supplied, dict) or set(supplied) != set(NAMES):
            raise SystemExit("Map must contain exactly the four provider names")
        for key, value in supplied.items():
            if not isinstance(value, str) or (value and not value.startswith("https://")):
                raise SystemExit(f"Provider URL for {key} must be HTTPS or blank")
        data = supplied
    map_file = assets / "dreamcast_provider_map.json"
    if args.mapping or not map_file.exists():
        map_file.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    catalog = folder / "DreamcastProviderCatalog.kt"
    catalog_content = """package com.streamvault.feature.provider.setup

import android.content.Context
import org.json.JSONObject

internal data class DreamcastProviderChoice(val name: String, val url: String)

internal object DreamcastProviderCatalog {
    private val names = listOf("DreamCAST TV", "Klepto TV", "Strong", "IPTVeditor")

    fun load(context: Context): List<DreamcastProviderChoice> {
        val entries = runCatching {
            JSONObject(
                context.assets.open("dreamcast_provider_map.json")
                    .bufferedReader().use { it.readText() }
            )
        }.getOrNull()
        return names.map { name ->
            DreamcastProviderChoice(name, entries?.optString(name).orEmpty())
        }
    }
}
"""
    if catalog.exists() and catalog.read_text(encoding="utf-8") != catalog_content:
        raise SystemExit(f"Refusing to overwrite custom provider catalog: {catalog}")
    catalog.write_text(catalog_content, encoding="utf-8")

    src = target.read_text(encoding="utf-8")
    marker = "// DreamCAST provider dropdown (tracked AndroidTV overlay)"
    if marker in src:
        print("Provider chooser already present; config refreshed.")
        return
    anchor = """    ProviderTextField(
        value = serverUrl,
        onValueChange = onServerUrlChange,
        placeholder = stringResource(R.string.setup_server_hint),"""
    if src.count(anchor) != 1:
        raise SystemExit("Expected one Xtream server field; upstream source has changed")
    # Add only new imports; retain upstream code as-is.
    additions = [
        "import androidx.compose.foundation.layout.Box",
        "import androidx.compose.material3.DropdownMenu",
        "import androidx.compose.material3.DropdownMenuItem",
        "import androidx.compose.runtime.getValue",
        "import androidx.compose.runtime.mutableStateOf",
        "import androidx.compose.runtime.remember",
        "import androidx.compose.runtime.saveable.rememberSaveable",
        "import androidx.compose.runtime.setValue",
        "import androidx.compose.ui.platform.LocalContext",
        "import com.streamvault.core.ui.interaction.TvButton",
    ]
    for item in additions:
        if item not in src:
            src = src.replace("import androidx.compose.foundation.text.KeyboardOptions",
                              item + "\nimport androidx.compose.foundation.text.KeyboardOptions", 1)
    section = """    // DreamCAST provider dropdown (tracked AndroidTV overlay)
    val context = LocalContext.current
    val choices = remember(context) {
        DreamcastProviderCatalog.load(context)
    }
    var expanded by remember { mutableStateOf(false) }
    var selectedProvider by rememberSaveable { mutableStateOf("") }
    val mappedUrl = choices.firstOrNull { it.name == selectedProvider }?.url.orEmpty()
    if (!uiState.isEditing) {
        Box {
            TvButton(onClick = { expanded = true }) {
                Text(
                    text = selectedProvider.ifEmpty {
                        stringResource(R.string.setup_provider_title)
                    }
                )
            }
            DropdownMenu(
                expanded = expanded,
                onDismissRequest = { expanded = false }
            ) {
                choices.forEach { option ->
                    DropdownMenuItem(
                        text = { Text(option.name) },
                        onClick = {
                            expanded = false
                            selectedProvider = option.name
                            onServerUrlChange(option.url)
                        }
                    )
                }
            }
        }
    }
    // Keep the manual URL field available until a valid URL mapping exists.
    // Do not hide the server field while editing an existing provider.
    if (uiState.isEditing || mappedUrl.isBlank()) {
"""
    replacement = section + anchor
    src = src.replace(anchor, replacement, 1)
    end_anchor = """    ProviderTextField(
        value = username,"""
    if src.count(end_anchor) != 1:
        raise SystemExit("Expected one Xtream username field")
    src = src.replace(end_anchor, "    }\n" + end_anchor, 1)
    # Avoid malformed Kotlin from a partial patch.
    if marker not in src or src.count("if (uiState.isEditing || mappedUrl.isBlank()) {") != 1:
        raise SystemExit("Provider patch verification failed")
    target.write_text(src, encoding="utf-8")
    print("Installed provider selector: " + ", ".join(NAMES))
    print("Unmapped choices leave the manual URL field visible.")
    print("This is a development overlay, not the authenticated remote provider registry.")

if __name__ == "__main__":
    main()
