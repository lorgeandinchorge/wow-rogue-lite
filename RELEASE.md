# Release Packaging

Use the release script to create a CurseForge zip from a whitelist of addon files.

This avoids accidentally shipping:

- AI prompt files
- design notes
- smoke test docs
- `.cursor` files
- temporary files
- anything else not explicitly part of the addon

## Recommended Workflow

Run this from the addon root:

```powershell
.\Build-CurseForgeRelease.ps1
```

The script will:

1. Find the addon `.toc` file.
2. Read every real addon file listed in the `.toc`.
3. Add any optional extra release files listed in `release-extra-files.txt`.
4. Build a clean zip in `dist\`.

## Why This Is Safe

The package is built from a whitelist, not a blacklist.

That means files like these are excluded automatically unless you explicitly opt in:

- `AI_MANAGER_PROMPTS.md`
- `DESIGN_Step12_BoonBurden.md`
- `SMOKE_TEST.md`
- `CURSEFORGE_DESCRIPTION.md`
- `.cursor\...`
- `*.tmp.*`

## Included Files

The script always includes:

- the `.toc` file
- every file referenced by the `.toc`

The script optionally includes:

- anything listed in `release-extra-files.txt`

Right now that extra file list is:

```text
WRL icon.png
```

## Output

The zip is written to:

```text
dist\WoWRoguelite-v<version>.zip
```

The version is read directly from:

```text
## Version: ...
```

inside `WoWRoguelite.toc`.

## Recommendation

For this project, this is the best long-term approach:

1. Keep development docs in the repo if you want them.
2. Never upload the repo folder directly.
3. Always upload the zip produced by `Build-CurseForgeRelease.ps1`.
4. Let the `.toc` stay the source of truth for shipped addon code.
