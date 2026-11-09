# VVV (Virtual Volumes View) 2.0 — evvvolved

VVV catalogs the content of removable volumes (external drives, CDs, DVDs) so you can
browse and search them offline. Folders and files can also be arranged in a virtual
file system that holds files from many volumes.

This is an independent continuation of [VVV](https://vvvapp.sourceforge.net) by
Fulvio Senore and the VVV team. It started from the Apple Silicon fork by
Sven Varkel and now focuses on Windows. The version 2.0 signals that catalogs
created by pre-2.0 versions must be converted once (see below).

## What changed from VVV 1.5

**Windows (the main platform here):**

- Native 64-bit build with CMake and Visual Studio (32-bit was dropped with 2.0).
- Per-monitor high-DPI support: the whole UI, toolbar and icons scale with the
  display; window and column layouts are stored DPI-independent.
- Modernized toolchain: wxWidgets 3.2.8, TagLib 2.3, and the embedded
  database engine moved from Firebird 2.1 to **Firebird 5**.
- Old catalogs use the Firebird 2 on-disk format and are detected early, and
  the app can convert them itself (see below); command-line mode reports the
  needed conversion to `stderr` and no longer hangs.
- Scanning a folder reads it in one pass instead of one query per file, and
  long paths (>260 characters) are supported.
- Catalog structure version stayed at 24, so catalogs created with the
  modernized app still have the same schema — only the on-disk format (ODS)
  changed with the engine.

**macOS (inherited from the Apple Silicon fork):**
native arm64 build (wxWidgets 3.3, TagLib 2, Firebird 5 from Homebrew),
self-contained `VVV.app`, old-catalog conversion inside the app.

## Converting catalogs from VVV 1.5 and older

Old catalogs use the Firebird 2 on-disk format (ODS 11), and Firebird 5 cannot
open it. They must be converted once.

- **Windows / Linux:** the app converts the catalog in place. Open the old
  catalog, answer Yes, and the app replaces the file with its new-format copy
  while keeping the original unchanged next to it as `<name>-vvv15.vvv` (a
  number is appended if that name is taken), so it stays usable with VVV 1.5.
  The row counts of every table are verified before the switch; plan free
  space for roughly the old catalog size. The old engine needed to read the
  ODS 11 format (a trimmed Firebird 2.5: `gbak` and `isql`) is bundled in a
  `firebird-2.5` subfolder next to the program — no installation and no
  network access. Without that subfolder the app explains what is missing.
- **Standalone converter (fallback):** the self-contained `catalog-converter`
  folder remains useful for mass conversions (wildcards, drag several files
  onto `convert-old-catalog.cmd`) and is available from the
  [Releases page](https://github.com/Bro-Account/evvvolved/releases). It
  bundles every engine it needs and can convert many catalogs in one run —
  one failing catalog does not stop the others.
- **macOS:** the app converts it in place: open the old catalog, answer Yes and
  pick a name for the new one (default `<name>-fb5.vvv`). From a source
  checkout, `scripts/migrate-catalog.sh` does the same on the command line.

## Building on Windows

Requirements: Visual Studio 2022/2026 Build Tools with the C++ CMake tools
component (Visual Studio 18 2026 generator tested), Windows PowerShell 5.1.

Populate a `deps/` folder next to (or one level above) this checkout:

```text
deps\wxWidgets-3.2.8-x64     official wxWidgets 3.2.8 MSVC prebuilt DLLs (+ headers)
deps\taglib-install-x64      TagLib 2.3.1 static build (lib\tag.lib + include\taglib)
deps\firebird-5.0.4-x64      Firebird 5.0.4 runtime for the embedded engine
```

Then from this repository root:

```powershell
.\build.ps1
```

The script configures, builds and stages a `run-x64/` folder that contains the
application, the wxWidgets DLLs and the Firebird 5 runtime — self-contained,
runnable as-is. `build-x64/` holds the CMake build tree.

Windows builds are 64-bit only since VVV 2.0.

## Building on macOS

Requirements: macOS on Apple Silicon, Xcode command line tools, Homebrew.

```bash
brew install cmake wxwidgets taglib
scripts/fetch-firebird.sh                  # official Firebird 5 arm64 pkg, extracted to deps/, no install
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PWD/build/install"
cmake --build build -j
cmake --install build                      # assembles and checks build/install/VVV.app
```

`cmake --install` fails if any library in the bundle still points outside the
bundle or macOS. The macOS release/signing workflow lives in
`scripts/release-macos.sh`.

## Known issues

- Windows: the Inno Setup installer script (`InnoSetup/vvv.iss`) is still the
  VVV 1.5 one and installs the obsolete Firebird 2.1 runtime; it needs a rework
  for the Firebird 5 file set. Until then, run the staged `run-<arch>` folders.
- macOS: search and cataloging a volume have not been tested through the GUI
  of this build yet.
- Catalog files only ever grow while the Firebird engine keeps pages allocated;
  they do not shrink automatically when drives are deleted. See *Catalog file
  size* below.

## Catalog file size

Like every Firebird database, a catalog grows while data is added; space is
reused for new records but no pages are ever returned to the file system.
Deleting drives does not shrink the file. The proven way to rebuild it at the
optimal size is a backup/restore cycle — the old-catalog conversion works this
way (the large size reductions in testing came from that rebuild), and the
**Compact** command in the File menu performs the same cycle on a current
catalog.

## Security notes

- The app opens no network ports and makes no network connections, unless you
  configure a remote Firebird server in the options.
- Untrusted input reaches C/C++ parsers: audio tags of files on cataloged
  volumes (TagLib), and catalogs (`.vvv`) someone else gives you (Firebird).
  Treat foreign catalogs and crafted media like any other file you open with a
  native app.
- Search terms and names are escaped before they go into SQL; no injection
  path was found.
- The Firebird password in the preferences is only obfuscated. It means
  nothing for local catalogs, but do not store a real password there if you
  connect to a remote Firebird server.
- The bundled libraries (Firebird, wxWidgets, TagLib, image and compression
  libraries) are frozen at build time: rebuild to pick up their security fixes.

## License

Contributors are listed in [CONTRIBUTORS.md](CONTRIBUTORS.md).

GPL v2 or later, see [COPYING](COPYING). Bundled components keep their own
licenses: Firebird (IPL/IDPL), IBPP (`src/ibpp/license.txt`), wxWidgets
(wxWindows Library Licence), TagLib (LGPL 2.1 / MPL 1.1).
