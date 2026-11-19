#!/usr/bin/env python3
"""Repair a generated StreamVault Android workspace where Gradle cannot resolve libs.

This is a reversible workaround. Gradle should discover libs.versions.toml by
default, but some generated workspaces fail to create the Kotlin DSL accessors.
Avoid auto-import collisions by using a distinct TOML basename for explicit
import. Do not touch app source, local.properties, or provider configuration.
"""
from pathlib import Path
import shutil
import sys

def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 repair-gradle-catalog.py <DreamCAST-StreamVault-dir>")
    root = Path(sys.argv[1]).expanduser().resolve()
    settings = root / "settings.gradle.kts"
    default_catalog = root / "gradle/libs.versions.toml"
    explicit_catalog = root / "gradle/dreamcast.versions.toml"
    if not settings.is_file():
        raise SystemExit(f"Missing settings file: {settings}")
    source = settings.read_text(encoding="utf-8")
    if "dependencyResolutionManagement {" not in source:
        raise SystemExit("Expected settings structure not found. Nothing changed.")
    marker = 'versionCatalogs {\n        create("libs") {\n            from(files("gradle/dreamcast.versions.toml"))\n        }\n    }'
    if marker in source and explicit_catalog.is_file():
        print("Catalog workaround is already installed.")
        return
    if "versionCatalogs {" in source:
        raise SystemExit("Existing custom version catalog found; refusing to edit.")
    if not default_catalog.is_file():
        raise SystemExit(f"Missing original catalog: {default_catalog}")
    if explicit_catalog.exists():
        raise SystemExit(f"Explicit catalog already exists: {explicit_catalog}; refusing overwrite.")
    backup = root / "settings.gradle.kts.before-dreamcast-catalog"
    if backup.exists():
        raise SystemExit(f"Backup already exists: {backup}; review it before retrying.")
    shutil.copy2(settings, backup)
    shutil.copy2(default_catalog, explicit_catalog)
    updated = source.replace(
        "dependencyResolutionManagement {",
        "dependencyResolutionManagement {\n    " + marker,
        1,
    )
    settings.write_text(updated, encoding="utf-8")
    # Disable Gradle's automatic import. Keep original bytes in named backup.
    default_catalog.rename(root / "gradle/libs.versions.toml.before-dreamcast-catalog")
    print("Explicit catalog configured. Settings backup:", backup)
    print("Original catalog backup:", root / "gradle/libs.versions.toml.before-dreamcast-catalog")
    print("Now run: ./gradlew help --no-configuration-cache")

if __name__ == "__main__":
    main()
