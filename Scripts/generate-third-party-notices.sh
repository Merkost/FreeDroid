#!/usr/bin/env bash
set -euo pipefail

# Run from repo root.
OUT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/THIRD_PARTY_NOTICES.md"

cat > "$OUT" <<'EOF'
# Third-Party Notices

FreeDroid uses the following third-party components.

---

## adb (Android Platform-Tools)

**License:** Apache License 2.0
**Source:** https://developer.android.com/tools/releases/platform-tools

A copy of the Apache 2.0 license is reproduced below.

```
                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   Copyright 2024 The Android Open Source Project

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

---

## libmtp

**License:** GNU Lesser General Public License v2.1
**Source:** https://libmtp.sourceforge.io/

libmtp is dynamically linked in FreeDroid. The corresponding source is available at the URL above.

---

## libusb

**License:** GNU Lesser General Public License v2.1
**Source:** https://libusb.info/

libusb is dynamically linked via libmtp.

---

## swift-async-algorithms

**License:** Apache License 2.0
**Source:** https://github.com/apple/swift-async-algorithms

---

## swift-dependencies

**License:** Apache License 2.0
**Source:** https://github.com/pointfreeco/swift-dependencies

---

## swift-snapshot-testing

**License:** MIT
**Source:** https://github.com/pointfreeco/swift-snapshot-testing

MIT License

Copyright (c) 2019 Point-Free, Inc.

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

---

## Sparkle 2

**License:** MIT
**Source:** https://sparkle-project.org/

MIT License

Copyright (c) 2006-2013 Andy Matuschak
Copyright (c) 2009-2013 Elgato Systems GmbH
Copyright (c) 2011-2014 Kornel Lesinski
Copyright (c) 2014 Matt Sinclair
Copyright (c) 2014-2023 Sparkle Project Contributors

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

EOF

echo "Wrote $OUT"
