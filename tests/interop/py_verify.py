"""ProtoBase's verifier with the ERP example's types registered (plan call C10).

Usage: python py_verify.py <directory> [--out FILE]

A bare ``python -m proto_db.tools.verify`` would read demo.erp.Invoice records as opaque
atoms. This imports examples/erp/erp_model.py (which registers demo.erp.*) and then runs
``proto_db.tools.verify.main`` unchanged; its exit status is this script's.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "examples" / "erp"))

import erp_model  # noqa: E402,F401  (registers demo.erp.*)
from proto_db.tools import verify  # noqa: E402

if __name__ == "__main__":
    sys.exit(verify.main(sys.argv[1:]))
