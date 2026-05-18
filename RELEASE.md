# Release Packaging

Releases are built and uploaded by GitHub Actions with the BigWigs packager.

The release workflow lives at:

```text
.github/workflows/release.yml
```

The package contents are controlled by:

```text
.pkgmeta
WoWRoguelite.toc
```

## Release A Version

1. Update `## Version:` in `WoWRoguelite.toc`.
2. Add notes to `CHANGELOG.md`.
3. Commit and push `main`.
4. Create and push a matching version tag. For hotfixes on a milestone release, use letter suffixes such as `0.3.0a`, `0.3.0b`, and `0.3.0c`.

Example:

```powershell
git add WoWRoguelite.toc WoWRoguelite.lua CHANGELOG.md README.md CURSEFORGE_DESCRIPTION.md RELEASE.md
git commit -m "Release v0.3.0a"
git push origin main
git tag -a v0.3.0a -m "0.3.0a GW2 UI theme texture hotfix"
git push origin v0.3.0a
```

The workflow packages the addon and uploads it to CurseForge.

## GitHub Settings

The CurseForge upload needs these GitHub Actions settings:

- Repository secret: `CF_API_KEY`
- Repository variable: `CF_PROJECT_ID`

Find `CF_PROJECT_ID` in the CurseForge project page's **About Project** box. Create `CF_API_KEY` from your CurseForge author API tokens page.

## What Gets Shipped

BigWigs packager reads `.pkgmeta` and `WoWRoguelite.toc`.

The shipped addon includes the addon folder, TOC file, Lua files listed in the TOC, and image assets. Development notes, tests, generated release folders, Cursor files, and temporary files are ignored.

Do not upload the repository folder directly to CurseForge. Use version tags and let GitHub Actions publish the release.
