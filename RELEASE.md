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

## GitHub Release Workflow

The repository also has a tag-based GitHub Actions workflow at:

```text
.github/workflows/release.yml
```

It does two things:

1. Builds the same clean zip with `Build-CurseForgeRelease.ps1`.
2. Attaches that zip to a GitHub release when you push a version tag such as `v0.1.0`.

To publish a new release:

```powershell
git tag v0.1.0
git push origin v0.1.0
```

Use the version from `WoWRoguelite.toc` for the tag name.

## CurseForge Upload Setup

The workflow can also upload tagged releases to CurseForge through the BigWigs packager.

Before that will run, add these in the GitHub repository settings:

- Repository secret: `CF_API_KEY`
- Repository variable: `CF_PROJECT_ID`

Find `CF_PROJECT_ID` in the CurseForge project page's **About Project** box after the project exists. Create `CF_API_KEY` from your CurseForge author API tokens page.

The CurseForge upload job is skipped until `CF_PROJECT_ID` is set, so the workflow is safe to add before the project has been approved.

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
WRL_MinimapIcon.png
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
4. Push version tags to let GitHub build releases.
5. Let the `.toc` stay the source of truth for shipped addon code.
