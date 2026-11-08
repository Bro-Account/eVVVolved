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
- Old catalogs use the Firebird 2 on-disk format and are detected early: the
  app shows conversion instructions instead of failing cryptically (also in
  command-line mode, which reports to `stderr` and no longer hangs).
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
open it. They must be converted once; the converter writes a new catalog next
to the old one and never modifies the original.

- **Windows:** use the self-contained `catalog-converter` folder (available
  from the [Releases page](https://github.com/Bro-Account/evvvolved/releases)).
  It bundles every engine it needs — no installation and no network access.
  Drag an old catalog file onto `convert-old-catalog.cmd`, or run
  `convert-old-catalog.cmd "D:\Catalogs\drives.vvv"`. It backs the old catalog
  up with a bundled Firebird 2.5 engine, restores the backup with Firebird 5
  (ODS 13), and compares the row counts of every table before keeping the
  result.
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
optimal size is a backup/restore cycle — exactly what the old-catalog
converter does (the large size reductions in testing came from that rebuild).

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
