# Third-party components — license summary

VVV is free software: GNU GPL 2 (see the file `COPYING` in the repository
root). This folder collects the license texts of the components that are
compiled into VVV or distributed with it. Each binary distribution (app
folder or installer) carries these texts in its `licenses/` subfolder.

| Component / files shipped | Version | License | Text in this folder |
|---|---|---|---|
| `vvv.exe` itself | 2.0 | GNU GPL 2 | `COPYING` (repository root; also staged) |
| Firebird 5 runtime (`fbclient.dll`, `icudt63.dll`, `icuin63.dll`, `icuuc63.dll`, `zlib1.dll`, …) | 5.0.4 | Firebird **IDPL** + **IPL** | `Firebird-5-IDPLicense.txt`, `Firebird-5-IPLicense.txt` |
| Firebird 2.5 conversion helper (`firebird-2.5\` subfolder, gbak/isql reading ODS 11) | 2.5.x | Firebird **IDPL** + **IPL** | the helper folder itself contains `IDPLicense.txt`/`IPLicense.txt` |
| ICU data/runtime libraries (shipped by Firebird 5) | 63 | ICU license | `ICU-63-LICENSE.txt` |
| zlib (`zlib1.dll`, shipped by Firebird 5) | 1.3.x | zlib license | `zlib-LICENSE.txt` |
| wxWidgets (`wx*32u_*.dll`, 13 DLLs) | 3.2.8 | wxWindows Library Licence (LGPL 2.1 + binary-use exception) | `wxWidgets-licence.txt` |
| TagLib (statically linked into `vvv.exe`) | 2.3.1 | LGPL 2.1 / MPL 1.1 (dual) | `TagLib-COPYING.LGPL.txt`, `TagLib-COPYING.MPL.txt` |
| IBPP (statically linked into `vvv.exe`) | 2006 copy | IBPP License | `IBPP-license.txt` |
| Visual C++ 2015–2022 runtime (`msvcp140*.dll`, `vcruntime140*.dll`), VC80 CRT inside the FB 2.5 helper | — | Microsoft redistributable terms | `MICROSOFT-CRT-NOTE.txt` |

Notes:

- The `catalog-converter` distribution (separate release artifact, repo
  `catalog-converter/` lives outside this source tree) contains the same
  Firebird engines; its `firebird-2.5/` and `firebird-5/` tool folders
  already ship `IDPLicense.txt`/`IPLicense.txt` in place. Add this file and
  the remaining missing texts when zipping that release (see the todo list).
- GPL 2 compatibility: wxWidgets carries an explicit licensing exception for
  binary distribution, TagLib is used under its MPL 1.1 wording, and zlib/ICU
  are permissive — combining them with the GPL-2 program is the established
  practice of the upstream VVV application (which always shipped with these
  components).
- License texts are reproduced verbatim from the official distribution of
  each component; do not edit them.
