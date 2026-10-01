"""Load private runtime settings without shell interpolation, then run gateway."""
import json
import os
from pathlib import Path
import runpy

root = Path(__file__).resolve().parent
settings = json.loads((root / "runtime.json").read_text())
os.environ.update({key: str(value) for key, value in settings.items()})
runpy.run_path(str(root / "main.py"), run_name="__main__")
