"""Builds docs/previews/easybid-dashboard.html: dashboard.src.html with the Supabase
client (MIT, vendor/) inlined so the page is one self-contained file."""
from pathlib import Path

here = Path(__file__).parent
src = (here / "dashboard.src.html").read_text()
lib = (here / "vendor" / "supabase-js-2.45.4.umd.js").read_text()
assert "</script" not in lib.lower()
# Webpack looks up its own script URL to load lazy chunks; an inlined script has none.
# The only lazy chunk is the Node.js "ws" shim, never used in browsers, so use "./".
PUBLIC_PATH_CHECK = 'if(!e)throw new Error("Automatic publicPath is not supported in this browser");'
assert lib.count(PUBLIC_PATH_CHECK) == 1
lib = lib.replace(PUBLIC_PATH_CHECK, 'if(!e)e="./";')
assert src.count("/*SUPABASE_JS*/") == 1
out = here.parent / "easybid-dashboard.html"
out.write_text(src.replace("/*SUPABASE_JS*/", lib))
print(out, out.stat().st_size, "bytes")
