# Third-party notices

This records inputs selected for the independently authored Blackgrid implementation, not a blanket clearance of the reference inventory. Blackgrid's project license remains unselected; the repository is private and this document does not authorize publication. No reference runtime/source or screenshots are shipped. M5 saved-panel OCR uses the installed Windows engine, and the M2 item vision runtime ships the pinned third-party binaries and OCR model; both are described below. Synthetic test fixtures were independently authored. M3 map artwork is independently acquired and bundled with the source-specific notices below; Blackgrid claims no ownership of that artwork.

## M3 map artwork and preparation

- **Interchange — Shebuka / Escape from Tarkov SVG Maps Project**: [served artwork](https://assets.tarkov.dev/maps/svg/Interchange.svg), SHA-256 `31a44112cd5fe33484ce6be7b7dc80d13db6077cba2583a4425ed94c665f47c4`, byte-identical to [repository source at revision `5a8b6115d1c0cf56f2ebaac1a96fa5ae3074d178`](https://github.com/the-hideout/tarkov-dev-svg-maps/blob/5a8b6115d1c0cf56f2ebaac1a96fa5ae3074d178/Interchange.svg). Its shared source viewBox is `0 0 1127.6852 947.02582`; this is not the older `b4c556ffcf85f9ef61a6b1b10c42f6339acd5d5e` 977.09998-square artwork. Artwork is published under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/). The revision-matched source `README.md` also explicitly prohibits cheating/unfair-advantage software, radar/ESP, cheat-client maps and automation/pixel-bots, and contains revocation wording. Both README and LICENSE.md are retained verbatim as prepared-pack `evidence/terms/svg-maps-README.md` and `evidence/terms/svg-maps-LICENSE.md`. Preserve attribution, noncommercial/share-alike conditions and published additional restrictions separately from the code licence. Preparation changes: dependency-closed source-ordered components with inherited floor context, CSS normalization, retained chained gradient references, native vector compilation and exact Structure-1/Structure-2 native drop-shadow effects; original source remains bundled as `evidence/interchange/Interchange.svg`.
- **Labs interactive — Tarkov.dev**: [creator/source](https://tarkov.dev/), tiles at `https://assets.tarkov.dev/maps/labs_v4/`. Preparation changes: decoded z4 tile validation and one shared display crop; original 2800-unit artwork frame and persisted pin revision are unchanged.
- **Icebreaker interactive — TarkovBOT.eu**: [creator](https://tarkovbot.eu/), tiles at `https://assets.tarkov.dev/maps/icebreaker/`. Attribution follows the interactive primary metadata, not its separate re3mr 2D map. Preparation changes: all 16 decoded tile families and shared display crop; source spelling `05_storage_ecurity` is retained.
- **Metadata and markers — Tarkov.dev**: [primary map metadata](https://raw.githubusercontent.com/the-hideout/tarkov-dev/main/src/data/maps.json), [source-position dataset](https://json.tarkov.dev/regular/maps). Independently frozen source URLs, bytes and SHA-256 hashes accompany the pack.

The representative vector's technical selection was corrected from Streets to Interchange because the frozen/current Streets source contains undefined `stairs-85`, `stairs-86` and `stairs-87` references. No missing artwork was repaired, stripped or fabricated. Static parsing of the current Interchange source found 70 unique IDs and 64 local-reference edges, with no missing targets. This establishes source dependency closure only, not successful compiler or Windows native-renderer qualification. Current authoritative metadata (SHA-256 `c53a327dcdcff67a49b9fe2d150731edb4c1611dfc2f75db2ce97444dee2ef77`, repository revision `ef62766bbd7ffb294c7184f9b8bfe8ed0f18320e`) supplies transform `[0.265,150.6,0.265,134.6]`, rotation 180 and bounds `[[598,-442],[-433,426]]`; source `First_Floor` is displayed as 2nd Floor, and `Second_Floor` as 3rd Floor.

The SVG repository licence is not a blanket licence for Labs/Icebreaker raster artwork. Published source and creator evidence is retained; a website software licence does not establish artwork permission. No separate owner-cleared permission is asserted. Inclusion follows the user's direction for this private implementation, not permission for a public release or a visibility change.

Preparation-only dependencies are pinned to `xml 6.6.1` ([MIT](https://github.com/renggli/dart-xml)), `image 4.8.0` ([MIT](https://github.com/brendan-duncan/image)) and `vector_graphics_compiler 1.3.0` ([BSD-3-Clause](https://github.com/flutter/packages/tree/main/packages/vector_graphics_compiler)); none requires a Flutter engine. Native runtime `vector_graphics 1.2.3` is qualified separately before its runtime commitment. Resolved transitive notices/lock are integrated by the parent after package resolution.

## M5 Map-owned saved-panel OCR

Map reads exfil/transit panels from explicitly supplied saved screenshots through the Windows `Windows.Media.Ocr` engine, matching the reference companion's backend. The engine, its recognizer language data and WIC/COM are installed OS components; nothing is copied or redistributed. The independently authored boundary is [`windows/ocr/panel_ocr.cpp`](windows/ocr/panel_ocr.cpp), built with the app and bound to its installed SHA-256. It uses no item Scanner worker or reference runtime. Microsoft documents the namespace as supported for packaged desktop apps; Blackgrid calls it unpackaged, as the reference companion does. Private image bytes and original filenames are not repository fixtures or shipped inputs.

The active all-map pack adds Factory, Customs, Woods, Shoreline, Reserve, Lighthouse, Streets of Tarkov, Ground Zero and Terminal artwork from the tarkov-dev SVG maps repository (each map's revision, SHA-256 and terms files are recorded in its manifest `attribution.artworkSource`; terms status `CC-BY-NC-SA-4.0-with-published-README-restrictions`), plus Labyrinth raster artwork from Tarkov.dev under the same no-owner-clearance status as the Labs and Icebreaker rasters. Customs and Reserve also use publisher raster overlays recorded with that status. `<use>` references to symbols the publisher deleted (Customs `path493`, two uses; Streets `stairs-85/86/87/90/92`, ten uses) render nothing, as in a browser and the reference WebView, and are dropped; nothing is invented, and any other missing symbol fails preparation. Private use is user-directed; no public redistribution right is asserted, and none is inferred from software licenses.

## M2 item vision runtime

The item vision runtime (ADR-0008) ships third-party native code and an OCR model in the Release bundle. Every input below is pinned in [`windows/vision/third_party.lock.json`](windows/vision/third_party.lock.json) by URL, version, size and SHA-256. The fetch tool and the CMake build refuse any other bytes, and the offline bundle integrity check (`mise run bundle:check`) confirms that each pinned SHA-256 appears in its entry here. These entries were recorded before the binaries entered a build. Inclusion follows the user's direction for this private implementation; it is not a public-release clearance.

<a id="opencv-4-13-0"></a>
### OpenCV 4.13.0

- **Use:** the `core` and `imgproc` modules, built from source as static libraries and linked into the independently authored `blackgrid_vision.dll` (`windows/vision/`). No other OpenCV module is built, and neither are IPP, OpenCL, ITT, Eigen, protobuf or any image codec.
- **Version:** 4.13.0 (tag commit `fe38fc608f6acb8b68953438a62305d8318f4fcd`)
- **Source:** <https://github.com/opencv/opencv/archive/refs/tags/4.13.0.zip> (byte-identical at <https://codeload.github.com/opencv/opencv/zip/refs/tags/4.13.0>)
- **SHA-256:** `431cb489d275da26526581c6735d7d7c0b00f190fe940b3217d386b77aef52c7` (100,344,657 bytes, source archive)
- **License:** Apache-2.0, verbatim in [Apache License 2.0](#apache-license-2-0) below (read from `opencv-4.13.0/LICENSE` in the pinned archive).
- **Bundled sub-components:** OpenCV `core` statically links its bundled zlib 1.3.1 (`3rdparty/zlib`) and Berkeley SoftFloat Release 3c (`modules/core/src/softfloat.cpp`). These are the licenses OpenCV's own install step records for this configuration (dlpack, also listed there, is used only by the Python bindings, which are not built). zlib terms, verbatim from `opencv-4.13.0/3rdparty/zlib/LICENSE`:

```text
Copyright notice:

 (C) 1995-2022 Jean-loup Gailly and Mark Adler

  This software is provided 'as-is', without any express or implied
  warranty.  In no event will the authors be held liable for any damages
  arising from the use of this software.

  Permission is granted to anyone to use this software for any purpose,
  including commercial applications, and to alter it and redistribute it
  freely, subject to the following restrictions:

  1. The origin of this software must not be misrepresented; you must not
     claim that you wrote the original software. If you use this software
     in a product, an acknowledgment in the product documentation would be
     appreciated but is not required.
  2. Altered source versions must be plainly marked as such, and must not be
     misrepresented as being the original software.
  3. This notice may not be removed or altered from any source distribution.

  Jean-loup Gailly        Mark Adler
  jloup@gzip.org          madler@alumni.caltech.edu
```

  SoftFloat terms, verbatim from the installed `licenses/SoftFloat-COPYING.txt`:

```text

License for Berkeley SoftFloat Release 3c

John R. Hauser
2017 February 10

The following applies to the whole of SoftFloat Release 3c as well as to
each source file individually.

Copyright 2011, 2012, 2013, 2014, 2015, 2016, 2017 The Regents of the
University of California.  All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice,
    this list of conditions, and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions, and the following disclaimer in the
    documentation and/or other materials provided with the distribution.

 3. Neither the name of the University nor the names of its contributors
    may be used to endorse or promote products derived from this software
    without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS "AS IS", AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE, ARE
DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

<a id="tesseract-5-0-0"></a>
### Tesseract OCR engine 5.0.0 (charlesw `Tesseract` NuGet package 5.2.0)

- **Use:** `tesseract50.dll`, extracted unmodified from `x64/tesseract50.dll` in the package and loaded through an independently authored `dart:ffi` binding. The package's managed .NET assemblies are not used or shipped.
- **Version:** Tesseract engine 5.0.0 (reported by `TessVersion()`), as built in package version 5.2.0
- **Source:** <https://www.nuget.org/api/v2/package/Tesseract/5.2.0> ([package project](https://github.com/charlesw/tesseract/), [engine](https://github.com/tesseract-ocr/tesseract/tree/5.0.0))
- **SHA-256:** package `202d82fc7c7d8384df7da57206d5e1f456ccdabd648c46e67cdfaa3a911d4795` (5,697,774 bytes); `tesseract50.dll` `de4d04ec75095374d98f5dd7a60d14d7e2e0f76589db693eccf7ae658be8cb2b` (2,788,352 bytes)
- **License:** Apache-2.0 for both the engine (`LICENSE` at tag 5.0.0) and the package (`LICENSE.txt` at tag 5.2.0). Each is verbatim identical to [Apache License 2.0](#apache-license-2-0) below.

<a id="leptonica-1-82-0"></a>
### Leptonica 1.82.0

- **Use:** `leptonica-1.82.0.dll`, extracted unmodified from `x64/leptonica-1.82.0.dll` in the charlesw `Tesseract` 5.2.0 package above. `tesseract50.dll` requires it; Blackgrid does not call it directly.
- **Version:** 1.82.0
- **Source:** <https://www.nuget.org/api/v2/package/Tesseract/5.2.0> (member `x64/leptonica-1.82.0.dll`; [upstream](https://github.com/DanBloomberg/leptonica/tree/1.82.0))
- **SHA-256:** `dfcb3e6ed0b16bc55bfdbcf53543cfe42a354b87c3e35bd3a95eebf005d73e76` (4,168,192 bytes)
- **License:** Leptonica's BSD-2-Clause-style license, verbatim from `leptonica-license.txt` at tag 1.82.0:

```text
/*====================================================================*
 -  Copyright (C) 2001-2020 Leptonica.  All rights reserved.
 -
 -  Redistribution and use in source and binary forms, with or without
 -  modification, are permitted provided that the following conditions
 -  are met:
 -  1. Redistributions of source code must retain the above copyright
 -     notice, this list of conditions and the following disclaimer.
 -  2. Redistributions in binary form must reproduce the above
 -     copyright notice, this list of conditions and the following
 -     disclaimer in the documentation and/or other materials
 -     provided with the distribution.
 -
 -  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 -  ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 -  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 -  A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL ANY
 -  CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 -  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 -  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 -  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 -  OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 -  NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 -  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *====================================================================*/
```

- **Statically embedded image libraries.** The prebuilt `leptonica-1.82.0.dll` embeds the libraries below, identified by their version strings in the pinned binary. Each one's terms are verbatim from the matching upstream release.
  - **zlib 1.2.13** (`zlib.h` at tag v1.2.13):

    ```text
      version 1.2.13, October 13th, 2022

      Copyright (C) 1995-2022 Jean-loup Gailly and Mark Adler

      This software is provided 'as-is', without any express or implied
      warranty.  In no event will the authors be held liable for any damages
      arising from the use of this software.

      Permission is granted to anyone to use this software for any purpose,
      including commercial applications, and to alter it and redistribute it
      freely, subject to the following restrictions:

      1. The origin of this software must not be misrepresented; you must not
         claim that you wrote the original software. If you use this software
         in a product, an acknowledgment in the product documentation would be
         appreciated but is not required.
      2. Altered source versions must be plainly marked as such, and must not be
         misrepresented as being the original software.
      3. This notice may not be removed or altered from any source distribution.

      Jean-loup Gailly        Mark Adler
      jloup@gzip.org          madler@alumni.caltech.edu
    ```

  - **libpng 1.6.37** (`LICENSE` at tag v1.6.37):

    ```text
    COPYRIGHT NOTICE, DISCLAIMER, and LICENSE
    =========================================

    PNG Reference Library License version 2
    ---------------------------------------

     * Copyright (c) 1995-2019 The PNG Reference Library Authors.
     * Copyright (c) 2018-2019 Cosmin Truta.
     * Copyright (c) 2000-2002, 2004, 2006-2018 Glenn Randers-Pehrson.
     * Copyright (c) 1996-1997 Andreas Dilger.
     * Copyright (c) 1995-1996 Guy Eric Schalnat, Group 42, Inc.

    The software is supplied "as is", without warranty of any kind,
    express or implied, including, without limitation, the warranties
    of merchantability, fitness for a particular purpose, title, and
    non-infringement.  In no event shall the Copyright owners, or
    anyone distributing the software, be liable for any damages or
    other liability, whether in contract, tort or otherwise, arising
    from, out of, or in connection with the software, or the use or
    other dealings in the software, even if advised of the possibility
    of such damage.

    Permission is hereby granted to use, copy, modify, and distribute
    this software, or portions hereof, for any purpose, without fee,
    subject to the following restrictions:

     1. The origin of this software must not be misrepresented; you
        must not claim that you wrote the original software.  If you
        use this software in a product, an acknowledgment in the product
        documentation would be appreciated, but is not required.

     2. Altered source versions must be plainly marked as such, and must
        not be misrepresented as being the original software.

     3. This Copyright notice may not be removed or altered from any
        source or altered source distribution.


    PNG Reference Library License version 1 (for libpng 0.5 through 1.6.35)
    -----------------------------------------------------------------------

    libpng versions 1.0.7, July 1, 2000, through 1.6.35, July 15, 2018 are
    Copyright (c) 2000-2002, 2004, 2006-2018 Glenn Randers-Pehrson, are
    derived from libpng-1.0.6, and are distributed according to the same
    disclaimer and license as libpng-1.0.6 with the following individuals
    added to the list of Contributing Authors:

        Simon-Pierre Cadieux
        Eric S. Raymond
        Mans Rullgard
        Cosmin Truta
        Gilles Vollant
        James Yu
        Mandar Sahastrabuddhe
        Google Inc.
        Vadim Barkov

    and with the following additions to the disclaimer:

        There is no warranty against interference with your enjoyment of
        the library or against infringement.  There is no warranty that our
        efforts or the library will fulfill any of your particular purposes
        or needs.  This library is provided with all faults, and the entire
        risk of satisfactory quality, performance, accuracy, and effort is
        with the user.

    Some files in the "contrib" directory and some configure-generated
    files that are distributed with libpng have other copyright owners, and
    are released under other open source licenses.

    libpng versions 0.97, January 1998, through 1.0.6, March 20, 2000, are
    Copyright (c) 1998-2000 Glenn Randers-Pehrson, are derived from
    libpng-0.96, and are distributed according to the same disclaimer and
    license as libpng-0.96, with the following individuals added to the
    list of Contributing Authors:

        Tom Lane
        Glenn Randers-Pehrson
        Willem van Schaik

    libpng versions 0.89, June 1996, through 0.96, May 1997, are
    Copyright (c) 1996-1997 Andreas Dilger, are derived from libpng-0.88,
    and are distributed according to the same disclaimer and license as
    libpng-0.88, with the following individuals added to the list of
    Contributing Authors:

        John Bowler
        Kevin Bracey
        Sam Bushell
        Magnus Holmgren
        Greg Roelofs
        Tom Tanner

    Some files in the "scripts" directory have other copyright owners,
    but are released under this license.

    libpng versions 0.5, May 1995, through 0.88, January 1996, are
    Copyright (c) 1995-1996 Guy Eric Schalnat, Group 42, Inc.

    For the purposes of this copyright and license, "Contributing Authors"
    is defined as the following set of individuals:

        Andreas Dilger
        Dave Martindale
        Guy Eric Schalnat
        Paul Schmidt
        Tim Wegner

    The PNG Reference Library is supplied "AS IS".  The Contributing
    Authors and Group 42, Inc. disclaim all warranties, expressed or
    implied, including, without limitation, the warranties of
    merchantability and of fitness for any purpose.  The Contributing
    Authors and Group 42, Inc. assume no liability for direct, indirect,
    incidental, special, exemplary, or consequential damages, which may
    result from the use of the PNG Reference Library, even if advised of
    the possibility of such damage.

    Permission is hereby granted to use, copy, modify, and distribute this
    source code, or portions hereof, for any purpose, without fee, subject
    to the following restrictions:

     1. The origin of this source code must not be misrepresented.

     2. Altered versions must be plainly marked as such and must not
        be misrepresented as being the original source.

     3. This Copyright notice may not be removed or altered from any
        source or altered source distribution.

    The Contributing Authors and Group 42, Inc. specifically permit,
    without fee, and encourage the use of this source code as a component
    to supporting the PNG file format in commercial products.  If you use
    this source code in a product, acknowledgment is not required but would
    be appreciated.
    ```

  - **libjpeg-turbo 2.1.4.** This software is based in part on the work of the Independent JPEG Group. The terms come from `LICENSE.md` at tag 2.1.4:

    ```text
    libjpeg-turbo Licenses
    ======================

    libjpeg-turbo is covered by three compatible BSD-style open source licenses:

    - The IJG (Independent JPEG Group) License, which is listed in
      [README.ijg](README.ijg)

      This license applies to the libjpeg API library and associated programs
      (any code inherited from libjpeg, and any modifications to that code.)

    - The Modified (3-clause) BSD License, which is listed below

      This license covers the TurboJPEG API library and associated programs, as
      well as the build system.

    - The [zlib License](https://opensource.org/licenses/Zlib)

      This license is a subset of the other two, and it covers the libjpeg-turbo
      SIMD extensions.


    Complying with the libjpeg-turbo Licenses
    =========================================

    This section provides a roll-up of the libjpeg-turbo licensing terms, to the
    best of our understanding.

    1.  If you are distributing a modified version of the libjpeg-turbo source,
        then:

        1.  You cannot alter or remove any existing copyright or license notices
            from the source.

            **Origin**
            - Clause 1 of the IJG License
            - Clause 1 of the Modified BSD License
            - Clauses 1 and 3 of the zlib License

        2.  You must add your own copyright notice to the header of each source
            file you modified, so others can tell that you modified that file (if
            there is not an existing copyright header in that file, then you can
            simply add a notice stating that you modified the file.)

            **Origin**
            - Clause 1 of the IJG License
            - Clause 2 of the zlib License

        3.  You must include the IJG README file, and you must not alter any of the
            copyright or license text in that file.

            **Origin**
            - Clause 1 of the IJG License

    2.  If you are distributing only libjpeg-turbo binaries without the source, or
        if you are distributing an application that statically links with
        libjpeg-turbo, then:

        1.  Your product documentation must include a message stating:

            This software is based in part on the work of the Independent JPEG
            Group.

            **Origin**
            - Clause 2 of the IJG license

        2.  If your binary distribution includes or uses the TurboJPEG API, then
            your product documentation must include the text of the Modified BSD
            License (see below.)

            **Origin**
            - Clause 2 of the Modified BSD License

    3.  You cannot use the name of the IJG or The libjpeg-turbo Project or the
        contributors thereof in advertising, publicity, etc.

        **Origin**
        - IJG License
        - Clause 3 of the Modified BSD License

    4.  The IJG and The libjpeg-turbo Project do not warrant libjpeg-turbo to be
        free of defects, nor do we accept any liability for undesirable
        consequences resulting from your use of the software.

        **Origin**
        - IJG License
        - Modified BSD License
        - zlib License


    The Modified (3-clause) BSD License
    ===================================

    Copyright (C)2009-2022 D. R. Commander.  All Rights Reserved.<br>
    Copyright (C)2015 Viktor Szathmáry.  All Rights Reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:

    - Redistributions of source code must retain the above copyright notice,
      this list of conditions and the following disclaimer.
    - Redistributions in binary form must reproduce the above copyright notice,
      this list of conditions and the following disclaimer in the documentation
      and/or other materials provided with the distribution.
    - Neither the name of the libjpeg-turbo Project nor the names of its
      contributors may be used to endorse or promote products derived from this
      software without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS",
    AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
    IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
    ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE
    LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
    CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
    SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
    INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
    CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
    ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.


    Why Three Licenses?
    ===================

    The zlib License could have been used instead of the Modified (3-clause) BSD
    License, and since the IJG License effectively subsumes the distribution
    conditions of the zlib License, this would have effectively placed
    libjpeg-turbo binary distributions under the IJG License.  However, the IJG
    License specifically refers to the Independent JPEG Group and does not extend
    attribution and endorsement protections to other entities.  Thus, it was
    desirable to choose a license that granted us the same protections for new code
    that were granted to the IJG for code derived from their software.
    ```

    The IJG license is the LEGAL ISSUES section of `README.ijg` at tag 2.1.4:

    ```text
    LEGAL ISSUES
    ============

    In plain English:

    1. We don't promise that this software works.  (But if you find any bugs,
       please let us know!)
    2. You can use this software for whatever you want.  You don't have to pay us.
    3. You may not pretend that you wrote this software.  If you use it in a
       program, you must acknowledge somewhere in your documentation that
       you've used the IJG code.

    In legalese:

    The authors make NO WARRANTY or representation, either express or implied,
    with respect to this software, its quality, accuracy, merchantability, or
    fitness for a particular purpose.  This software is provided "AS IS", and you,
    its user, assume the entire risk as to its quality and accuracy.

    This software is copyright (C) 1991-2020, Thomas G. Lane, Guido Vollbeding.
    All Rights Reserved except as specified below.

    Permission is hereby granted to use, copy, modify, and distribute this
    software (or portions thereof) for any purpose, without fee, subject to these
    conditions:
    (1) If any part of the source code for this software is distributed, then this
    README file must be included, with this copyright and no-warranty notice
    unaltered; and any additions, deletions, or changes to the original files
    must be clearly indicated in accompanying documentation.
    (2) If only executable code is distributed, then the accompanying
    documentation must state that "this software is based in part on the work of
    the Independent JPEG Group".
    (3) Permission for use of this software is granted only if the user accepts
    full responsibility for any undesirable consequences; the authors accept
    NO LIABILITY for damages of any kind.

    These conditions apply to any software derived from or based on the IJG code,
    not just to the unmodified library.  If you use our work, you ought to
    acknowledge us.

    Permission is NOT granted for the use of any IJG author's name or company name
    in advertising or publicity relating to this software or products derived from
    it.  This software may be referred to only as "the Independent JPEG Group's
    software".

    We specifically permit and encourage the use of this software as the basis of
    commercial products, provided that all warranty or liability claims are
    assumed by the product vendor.
    ```

  - **libtiff 4.4.0** (`COPYRIGHT` at tag v4.4.0):

    ```text
    Copyright (c) 1988-1997 Sam Leffler
    Copyright (c) 1991-1997 Silicon Graphics, Inc.

    Permission to use, copy, modify, distribute, and sell this software and 
    its documentation for any purpose is hereby granted without fee, provided
    that (i) the above copyright notices and this permission notice appear in
    all copies of the software and related documentation, and (ii) the names of
    Sam Leffler and Silicon Graphics may not be used in any advertising or
    publicity relating to the software without the specific, prior written
    permission of Sam Leffler and Silicon Graphics.

    THE SOFTWARE IS PROVIDED "AS-IS" AND WITHOUT WARRANTY OF ANY KIND, 
    EXPRESS, IMPLIED OR OTHERWISE, INCLUDING WITHOUT LIMITATION, ANY 
    WARRANTY OF MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.  

    IN NO EVENT SHALL SAM LEFFLER OR SILICON GRAPHICS BE LIABLE FOR
    ANY SPECIAL, INCIDENTAL, INDIRECT OR CONSEQUENTIAL DAMAGES OF ANY KIND,
    OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
    WHETHER OR NOT ADVISED OF THE POSSIBILITY OF DAMAGE, AND ON ANY THEORY OF 
    LIABILITY, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE 
    OF THIS SOFTWARE.
    ```

<a id="tessdata-fast-4-1-0"></a>
### tessdata_fast 4.1.0 `eng.traineddata`

- **Use:** the English OCR model, installed unmodified at `data/vision/tessdata/eng.traineddata`.
- **Version:** 4.1.0 (tag commit `65727574dfcd264acbb0c3e07860e4e9e9b22185`)
- **Source:** <https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/4.1.0/eng.traineddata>
- **SHA-256:** `7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2` (4,113,088 bytes), identical to the M0 intake hash
- **License:** Apache-2.0 (`LICENSE` at tag 4.1.0), verbatim identical to [Apache License 2.0](#apache-license-2-0) below.

<a id="spleen-2-1-0"></a>
### Spleen 2.1.0 bitmap font (self-check sample, development only)

- **Use:** `tool/vision/make_self_check_sample.dart` renders the self-check title with `spleen-32x64.bdf`, halves it with a box filter, and writes `assets/vision/self_check/title.gray`. Only that rendered output is redistributed in the bundle (`data/vision/self_check/`). The font file is vendored at `tool/vision/fonts/spleen/` for reproducible regeneration and is not part of the application or the bundle.
- **Version:** 2.1.0
- **Source:** <https://github.com/fcambus/spleen/releases/download/2.1.0/spleen-2.1.0.tar.gz> (SHA-256 `8b47c56f1a6eb858fbcf9e34530557404b02fbb3455e38e64fb84473fd0c372f`)
- **File SHA-256:** `spleen-32x64.bdf` `8a6fbd024d11f57ec973291959a19c020465ccbdc0836d938e31e27d68e47e4b`; `LICENSE` `3cb3f3f5a795547d329828df881c80d923bfc75f65065c44ffa703ad78c678bd`
- **License:** BSD-2-Clause, Copyright (c) 2018-2024, Frederic Cambus, verbatim from `LICENSE`:

    Copyright (c) 2018-2024, Frederic Cambus
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:

      * Redistributions of source code must retain the above copyright
        notice, this list of conditions and the following disclaimer.

      * Redistributions in binary form must reproduce the above copyright
        notice, this list of conditions and the following disclaimer in the
        documentation and/or other materials provided with the distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
    AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
    IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
    ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS
    BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
    CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
    SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
    INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
    CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
    ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.

<a id="inspection-marker-template"></a>
### Inspection marker template (game UI artwork)

- **Status:** game UI artwork captured by the user, not covered by Blackgrid's licence. It is a 28x28 grayscale crop of the inspect-window magnifier glyph from a screenshot the user took of the game client. Blackgrid claims no ownership of it, and no public redistribution right is asserted. Inclusion follows the user's direction for this private implementation, not a public-release clearance.
- **Files:** `data/vision/marker/inspection_marker.gray` (SHA-256 `3b6771a1028cb438c14daf252e78fc9c1fe0cf8af79af5800b15681713c8e72f`); `data/vision/marker/inspection_marker.json` (SHA-256 `60321abd52ad2070508930b28c3c1c9b8fa724b3dc7af2fa260db2497ee162e3`). Source copies are under `assets/vision/marker/`.
- **Source screenshot SHA-256:** `4c46ea322d14fb28285a79c4fe74b46c37f28f5cd2138858ff6a8a5dcc0d3eb3` (3440x1440 client, footprint origin 1198,277). The screenshot is not committed.
- **Recipe:** `inspection-marker-v1`, produced by `tool/vision/make_marker_template.dart`: OpenCV-rounded BGR luma, a 21x21 footprint (trunc(16 x 4/3)) at the origin, deterministic cubic resize to 28x28.
- **Regeneration:** rerun the tool on the user's screenshot, then update both file hashes here in the same commit. `mise run bundle:check` fails on a stale entry.

<a id="microsoft-visual-cpp-runtime"></a>
### Microsoft Visual C++ runtime (app-local)

- **Use:** `msvcp140.dll`, `vcruntime140.dll` and `vcruntime140_1.dll`, copied unmodified by CMake `InstallRequiredSystemLibraries` from the build toolchain's `VC\Redist\MSVC\<version>\x64\Microsoft.VC<toolset>.CRT` directory. With these copies the bundle needs no system-installed redistributable.
- **Version:** the redistributable of the toolchain that builds the bundle. At this change that is Visual Studio 2026, Redist MSVC 14.51.36231, file version 14.51.36247.0. These files vary with the toolchain, so they are not pinned by SHA-256. Instead the bundle integrity check enforces a committed minimum file version per DLL (`tool/vision/bundle_inventory.json`).
- **Terms:** Distributable Code under the Microsoft Software License Terms for Visual Studio. Verbatim from the [Visual Studio 2026 distributable code list](https://learn.microsoft.com/en-us/visualstudio/releases/2026/redistribution) (`REDIST.TXT`):

```text
The following section is the "Distributable List" or the "REDIST.TXT" that is referenced in the "Distributable Code" section of the Microsoft Software License Terms for Visual Studio Enterprise, Visual Studio Professional, Visual Studio Community, and Visual Studio Build Tools ("the software"). If you have a validly licensed copy of such software, you may copy and distribute with your program the unmodified form of the files listed below, subject to the License Terms for the software.

Visual C++ Runtime Files

Subject to the License Terms for the software, you may copy and distribute the following files, unmodified, as a part of the installation package of your program:

- [VisualStudioFolder]\VC\Redist\MSVC\[version]\MergeModules\Microsoft_VC145_CRT_[arch].msm

- [VisualStudioFolder]\VC\Redist\MSVC\[version]\MergeModules\Microsoft_VC145_CXXAMP_[arch].msm

- [VisualStudioFolder]\VC\Redist\MSVC\[version]\MergeModules\Microsoft_VC145_MFCLOC_[arch].msm

- [VisualStudioFolder]\VC\Redist\MSVC\[version]\MergeModules\Microsoft_VC145_MFC_[arch].msm

- [VisualStudioFolder]\VC\Redist\MSVC\[version]\MergeModules\Microsoft_VC145_OpenMP_[arch].msm

Subject to the License Terms for the software, you may copy and distribute with your program any of the files within the following folder and its subfolders except as noted below. You may not modify these files.

- [VisualStudioFolder]\VC\redist

The same Visual C++ Runtime Redistributable package is available from Latest supported Visual C++ Redistributable downloads and Download Visual Studio Tools. Distribution of the Visual C++ Runtime Redistributable package, merge modules, and individual binaries obtained from those pages is limited to licensed Visual Studio users and is subject to its license terms.
```

<a id="dart-archive-4-3-0"></a>
### `package:archive` 4.3.0 (development only)

- **Use:** a pinned dev dependency of `tool/vision/fetch_runtime.dart`, which uses it to extract the two DLLs from the nupkg. It is not part of the application or the bundle.
- **Version:** 4.3.0
- **Source:** <https://pub.dev/packages/archive/versions/4.3.0>
- **License:** MIT, verbatim under [Map preparation MIT packages](#map-preparation-mit-packages) below (`package-root:archive/LICENSE`).

<a id="apache-license-2-0"></a>
### Apache License 2.0

This verbatim text is shared by OpenCV 4.13.0, the Tesseract 5.0.0 engine, the charlesw `Tesseract` 5.2.0 package and tessdata_fast 4.1.0. All four upstream files are byte-identical.

```text

                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

   APPENDIX: How to apply the Apache License to your work.

      To apply the Apache License to your work, attach the following
      boilerplate notice, with the fields enclosed by brackets "[]"
      replaced with your own identifying information. (Don't include
      the brackets!)  The text should be enclosed in the appropriate
      comment syntax for the file format. We also recommend that a
      file or class name and description of purpose be included on the
      same "printed page" as the copyright notice for easier
      identification within third-party archives.

   Copyright [yyyy] [name of copyright owner]

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
```

## Resolved selection

Versions come from the committed `pubspec.lock` and the pinned Flutter 3.47.6 / Dart 3.13.5 toolchain. Some transitive packages supply native build hooks rather than application Dart code; they are included conservatively in this record. Verbatim license texts below were read from the resolved packages through the official Dart tooling.

| Input | Resolved version | Use | Source |
| --- | --- | --- | --- |
| async | 2.13.1 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/async/versions/2.13.1) |
| characters | 1.4.1 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/characters/versions/1.4.1) |
| code_assets | 1.2.1 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/code_assets/versions/1.2.1) |
| collection | 1.19.1 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/collection/versions/1.19.1) |
| convert | 3.1.2 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/convert/versions/3.1.2) |
| crypto | 3.0.7 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/crypto/versions/3.0.7) |
| drift | 2.35.1 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/drift/versions/2.35.1) |
| ffi | 2.2.0 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/ffi/versions/2.2.0) |
| file | 7.0.1 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/file/versions/7.0.1) |
| flutter | Flutter 3.47.6 | Framework / desktop runtime | [Flutter](https://github.com/flutter/flutter/tree/3.47.6) |
| glob | 2.2.0 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/glob/versions/2.2.0) |
| hooks | 2.0.2 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/hooks/versions/2.0.2) |
| http | 1.6.0 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/http/versions/1.6.0) |
| http_parser | 4.1.2 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/http_parser/versions/4.1.2) |
| logging | 1.3.0 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/logging/versions/1.3.0) |
| material_color_utilities | 0.13.0 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/material_color_utilities/versions/0.13.0) |
| meta | 1.18.3 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/meta/versions/1.18.3) |
| native_toolchain_c | 0.19.2 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/native_toolchain_c/versions/0.19.2) |
| path | 1.9.1 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/path/versions/1.9.1) |
| pub_semver | 2.2.1 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/pub_semver/versions/2.2.1) |
| record_use | 0.6.0 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/record_use/versions/0.6.0) |
| sky_engine | Flutter 3.47.6 | Engine / aggregate native notices | [Flutter](https://github.com/flutter/flutter/tree/3.47.6) |
| source_span | 1.10.2 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/source_span/versions/1.10.2) |
| sqlite3 | 3.5.2 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/sqlite3/versions/3.5.2) |
| stack_trace | 1.12.2 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/stack_trace/versions/1.12.2) |
| stream_channel | 2.1.4 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/stream_channel/versions/2.1.4) |
| string_scanner | 1.4.1 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/string_scanner/versions/1.4.1) |
| term_glyph | 1.2.2 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/term_glyph/versions/1.2.2) |
| typed_data | 1.4.0 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/typed_data/versions/1.4.0) |
| vector_graphics | 1.2.3 | Native compiled-vector rendering | [pub.dev](https://pub.dev/packages/vector_graphics/versions/1.2.3) |
| vector_graphics_codec | 1.1.13 | Compiled-vector decoding | [pub.dev](https://pub.dev/packages/vector_graphics_codec/versions/1.1.13) |
| vector_graphics_compiler | 1.3.0 | Offline map preparation | [pub.dev](https://pub.dev/packages/vector_graphics_compiler/versions/1.3.0) |
| xml | 6.6.1 | Offline SVG dependency/style preparation | [pub.dev](https://pub.dev/packages/xml/versions/6.6.1) |
| image | 4.8.0 | Offline PNG validation | [pub.dev](https://pub.dev/packages/image/versions/4.8.0) |
| petitparser | 7.0.2 | Preparation parser dependency | [pub.dev](https://pub.dev/packages/petitparser/versions/7.0.2) |
| archive | 4.3.0 | Preparation image dependency | [pub.dev](https://pub.dev/packages/archive/versions/4.3.0) |
| posix | 6.5.2 | Preparation image dependency | [pub.dev](https://pub.dev/packages/posix/versions/6.5.2) |
| vector_math | 2.4.0 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/vector_math/versions/2.4.0) |
| web | 1.1.1 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/web/versions/1.1.1) |
| yaml | 3.1.4 | Application dependency or native build hook | [pub.dev](https://pub.dev/packages/yaml/versions/3.1.4) |
| drift_dev | 2.35.1 | Development / generation / tests | [pub.dev](https://pub.dev/packages/drift_dev/versions/2.35.1) |
| build_runner | 2.16.1 | Development / generation / tests | [pub.dev](https://pub.dev/packages/build_runner/versions/2.16.1) |
| test | 1.31.1 | Development / generation / tests | [pub.dev](https://pub.dev/packages/test/versions/1.31.1) |
| flutter_lints | 6.0.0 | Development / generation / tests | [pub.dev](https://pub.dev/packages/flutter_lints/versions/6.0.0) |

**SQLite native library:** its deliverable code is [dedicated to the public domain by its authors](https://www.sqlite.org/copyright.html). This does not apply to every SQLite build script or replace the MIT license of the separate Dart `sqlite3` wrapper. Native-library selection and packaging follow the resolved wrapper's hooks.

**Flutter engine:** the pinned SDK supplies aggregate native third-party notices in `sky_engine/LICENSE`; preserve those framework/engine notices when distributing a complete Flutter bundle. The aggregate is not duplicated here. This dependency-selection record is not a clean-machine release or public-publication qualification.

**Windows APIs:** Blackgrid calls the installed Windows current-user DPAPI, known-folder and file-replacement APIs through a narrowly authored runner channel. No Win32 wrapper package or reference protection code is selected.

**Remote data:** production GETs use [json.tarkov.dev](https://json.tarkov.dev/endpoints) and the read-only [Tracker API](https://api.tarkovtracker.org/openapi.json). Hosting and API availability are not blanket redistribution licenses for game data, artwork or private progress. Credentials and personal progress are not included in repository fixtures, local history, notices or diagnostics. Future asset selection and public distribution retain their own rights gates.

## Verbatim selected package licenses

### Map vector packages: vector_graphics and vector_graphics_compiler

The resolved `package-root:vector_graphics/LICENSE` and
`package-root:vector_graphics_compiler/LICENSE` contain the same notice:

```text
Copyright 2013 The Flutter Authors

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google Inc. nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### File "package-root:vector_graphics_codec/LICENSE"

```text
Copyright 2013 The Flutter Authors. All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google Inc. nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### Map preparation MIT packages

The resolved XML, image, parser and archive notices carry these exact
copyright lines:

- `package-root:xml/LICENSE`: `Copyright (c) 2006-2025 Lukas Renggli.`
- `package-root:image/LICENSE`: `Copyright (c) 2013-2022 Brendan Duncan.`
- `package-root:petitparser/LICENSE`: `Copyright (c) 2006-2024 Lukas Renggli.`
- `package-root:archive/LICENSE`: `Copyright (c) 2013-2021 Brendan Duncan.`

Each of those four notices is headed `The MIT License`, follows its copyright
with `All rights reserved.`, and includes this identical permission and disclaimer:

```text
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

### File "package-root:posix/LICENSE"

```text
MIT License

Copyright (c) 2020 Brett Sutton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## File "package-root:async/LICENSE":


Copyright 2015, the Dart project authors. 

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:build_runner/LICENSE":


Copyright 2016, the Dart project authors. 

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:characters/LICENSE":


Copyright 2019, the Dart project authors. 

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:code_assets/LICENSE":


Copyright 2025, the Dart project authors.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:collection/LICENSE":


Copyright 2015, the Dart project authors. 

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:convert/LICENSE":


Copyright 2015, the Dart project authors.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:crypto/LICENSE":


Copyright 2015, the Dart project authors.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:drift/LICENSE":


MIT License

Copyright (c) 2021 Simon Binder

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.






## File "package-root:drift_dev/LICENSE":


MIT License

Copyright (c) 2021 Simon Binder

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.






## File "package-root:ffi/LICENSE":


Copyright 2019, the Dart project authors. 

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:file/LICENSE":


Copyright 2017, the Dart project authors. All rights reserved.
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google Inc. nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.





## File "package-root:flutter/LICENSE":


Copyright 2014 The Flutter Authors. All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google Inc. nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:flutter_lints/LICENSE":


Copyright 2013 The Flutter Authors. All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google Inc. nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:glob/LICENSE":


Copyright 2014, the Dart project authors. 

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:hooks/LICENSE":


Copyright 2025, the Dart project authors.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:http/LICENSE":


Copyright 2014, the Dart project authors. 

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:http_parser/LICENSE":


Copyright 2014, the Dart project authors. 

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:logging/LICENSE":


Copyright 2013, the Dart project authors. 

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:material_color_utilities/LICENSE":



                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

   APPENDIX: How to apply the Apache License to your work.

   To apply the Apache License to your work, attach the following
   boilerplate notice, with the fields enclosed by brackets "[]"
   replaced with your own identifying information. (Don't include
   the brackets!)  The text should be enclosed in the appropriate
   comment syntax for the file format. We also recommend that a
   file or class name and description of purpose be included on the
   same "printed page" as the copyright notice for easier
   identification within third-party archives.

   Copyright 2021 Google LLC

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.






## File "package-root:meta/LICENSE":


Copyright 2016, the Dart project authors.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:native_toolchain_c/LICENSE":


Copyright 2023, the Dart project authors.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:path/LICENSE":


Copyright 2014, the Dart project authors. 

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:pub_semver/LICENSE":


Copyright 2014, the Dart project authors. 

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:record_use/LICENSE":


Copyright 2024, the Dart project authors.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






[Showing lines 1-997 of 31216. Use :998 to continue]

## File "package-root:source_span/LICENSE":


Copyright 2014, the Dart project authors. 

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:sqlite3/LICENSE":


MIT License

Copyright (c) 2020 Simon Binder

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.





## File "package-root:stack_trace/LICENSE":


Copyright 2014, the Dart project authors.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:stream_channel/LICENSE":


Copyright 2015, the Dart project authors. 

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:string_scanner/LICENSE":


Copyright 2014, the Dart project authors. 

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:term_glyph/LICENSE":


Copyright 2017, the Dart project authors. 

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:test/LICENSE":


Copyright 2014, the Dart project authors. 

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:typed_data/LICENSE":


Copyright 2015, the Dart project authors. 

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:vector_math/LICENSE":


Copyright 2013 The Flutter Authors

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google Inc. nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:web/LICENSE":


Copyright 2023, the Dart project authors.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.






## File "package-root:yaml/LICENSE":


Copyright (c) 2014, the Dart project authors.
Copyright (c) 2006, Kirill Simonov.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.



