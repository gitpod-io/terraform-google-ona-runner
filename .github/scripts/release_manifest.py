import json
import re
import sys
import urllib.request
from pathlib import Path


IMAGE_FIELDS = ("runner_image", "proxy_image", "prometheus_image", "node_exporter_image")


def release_manifest(locals_text):
    images = {}
    for field in IMAGE_FIELDS:
        matches = re.findall(
            rf'^\s*default_{field}\s*=\s*"([^"\n]+)"\s*$',
            locals_text,
            re.MULTILINE,
        )
        if len(matches) != 1:
            raise ValueError(f"Expected one literal default_{field} in locals.tf")
        images[field] = matches[0]

    tag = re.search(r":([0-9]{8}\.[0-9]+)$", images["runner_image"])
    if tag is None:
        raise ValueError("Default runner image must have a YYYYMMDD.N release tag")
    version = tag[1]
    url = f"https://storage.googleapis.com/gitpod-runner-releases/gcp/releases/{version}/manifest.json"
    with urllib.request.urlopen(url, timeout=30) as response:
        manifest = json.load(response)

    for field, expected in {"version": version, **images}.items():
        if manifest.get(field) != expected:
            raise ValueError(f"Release manifest {field} does not match module default: {expected}")
    for field in ("cli_url", "supervisor_url", "vm_image"):
        if not isinstance(manifest.get(field), str) or not manifest[field].strip():
            raise ValueError(f"Release manifest is missing {field}")
    return manifest


if __name__ == "__main__":
    print(json.dumps(release_manifest(Path(sys.argv[1]).read_text()), indent=2))
