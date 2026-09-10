"""Exercise the root TLS resources with real providers and a local Secret Manager API."""

import argparse
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlsplit
import zipfile


class SecretManager(BaseHTTPRequestHandler):
    records = {}
    payloads = {}
    fail_pair = False
    lock = threading.Lock()

    def log_message(self, *_args):
        pass

    def reply(self, status, value):
        body = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def name(self):
        return unquote(urlsplit(self.path).path).removeprefix("/v1/")

    def do_GET(self):
        with self.lock:
            name = self.name()
            access = name.endswith(":access")
            name = name.removesuffix(":access")
            if name not in self.records:
                self.reply(404, {"error": {"code": 404, "message": "Missing test secret"}})
            elif access:
                self.reply(200, {"name": name, "payload": {
                    "data": base64.b64encode(self.payloads[name].encode()).decode()
                }})
            else:
                self.reply(200, self.records[name])

    def do_POST(self):
        with self.lock:
            name = self.name()
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or "{}")
            if name.endswith("/secrets"):
                secret_id = parse_qs(urlsplit(self.path).query)["secretId"][0]
                name += "/" + secret_id
                self.records[name] = dict(body, name=name, createTime="2026-09-10T00:00:00Z")
                self.reply(200, self.records[name])
            elif name.endswith(":addVersion"):
                secret = name.removesuffix(":addVersion")
                if self.fail_pair and secret.endswith("-tls"):
                    self.reply(400, {"error": {"code": 400, "message": "Injected pair write failure"}})
                    return
                version = 1 + sum(n.startswith(secret + "/versions/") for n in self.records)
                name = f"{secret}/versions/{version}"
                self.records[name] = {"name": name, "createTime": "2026-09-10T00:00:00Z", "state": "ENABLED"}
                self.payloads[name] = base64.b64decode(body["payload"]["data"]).decode()
                self.reply(200, self.records[name])
            elif name.endswith((":enable", ":disable", ":destroy")):
                name, action = name.rsplit(":", 1)
                self.records[name]["state"] = {"enable": "ENABLED", "disable": "DISABLED", "destroy": "DESTROYED"}[action]
                self.reply(200, self.records[name])
            else:
                self.reply(400, {"error": {"code": 400, "message": "Unexpected test API request"}})

    def do_DELETE(self):
        with self.lock:
            name = self.name()
            for record in list(self.records):
                if record == name or record.startswith(name + "/versions/"):
                    del self.records[record]
            self.reply(200, {})


def main(google_version):
    root = Path(tempfile.mkdtemp(prefix="internal-runner-tls-"))
    root.chmod(0o700)
    shutil.copyfile(Path(__file__).resolve().parents[1] / "internal-runner-tls.tf",
                    root / "internal-runner-tls.tf")
    server = ThreadingHTTPServer(("127.0.0.1", 0), SecretManager)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("TF_", "GOOGLE_", "GCLOUD_", "CLOUDSDK_"))}
    if "TF_PLUGIN_CACHE_DIR" in os.environ:
        env["TF_PLUGIN_CACHE_DIR"] = os.environ["TF_PLUGIN_CACHE_DIR"]
    env["TF_IN_AUTOMATION"] = "true"

    def tf(*args, allowed=(0,)):
        result = subprocess.run(["terraform", *args], cwd=root, env=env,
                                text=True, capture_output=True, timeout=180)
        if result.returncode not in allowed:
            errors = [line for line in result.stderr.splitlines() if line.startswith("Error:")]
            raise RuntimeError(f"terraform {args[0]} failed: {'; '.join(errors)}")
        return result

    def write_config(generation=1, prefix="runner", kms_key_name=None):
        config = {
            "terraform": {"required_version": ">= 1.11", "required_providers": {
                "google": {"source": "hashicorp/google", "version": google_version},
                "tls": {"source": "hashicorp/tls", "version": "4.4.0"},
            }},
            "provider": {"google": {
                "project": "synthetic-project", "access_token": "local-test-only",
                "secret_manager_custom_endpoint": f"http://127.0.0.1:{server.server_port}/v1/",
            }},
            "variable": {
                "project_id": {"default": "synthetic-project"},
                "region": {"default": "us-central1"},
                "runner_id": {"default": prefix},
                "restrict_ingress": {"default": True},
                "internal_runner_tls_generation": {"default": generation},
            },
            "locals": {
                "internal_runner_hostname": "runner.synthetic.internal",
                "kms_key_name": kms_key_name,
                "runner_labels": {},
                "manage_service_account_iam_policies": False,
                "runner_sa_email": "unused@synthetic-project.iam.gserviceaccount.com",
            },
            "resource": {"google_kms_crypto_key_iam_member": {"google_secretmanager": {
                "count": 0,
                "crypto_key_id": "projects/synthetic-project/locations/us-central1/keyRings/runner/cryptoKeys/secrets",
                "role": "roles/cloudkms.cryptoKeyEncrypterDecrypter",
                "member": "serviceAccount:unused@synthetic-project.iam.gserviceaccount.com",
            }}},
            "output": {
                "certificate": {"value": "${tls_self_signed_cert.internal_runner[0].cert_pem}"},
                "secret": {"value": '${google_secret_manager_secret.internal_runner_tls["tls"].id}'},
                "version": {"value": "${google_secret_manager_secret_version.internal_runner_tls[0].version}"},
            },
        }
        (root / "main.tf.json").write_text(json.dumps(config))

    def openssl(args, value):
        result = subprocess.run(["openssl", *args], input=value.encode(), capture_output=True, timeout=15)
        if result.returncode:
            raise RuntimeError("OpenSSL rejected the test identity")
        return result.stdout

    def verify_pair():
        outputs = json.loads(tf("output", "-json").stdout)
        name = outputs["secret"]["value"] + "/versions/" + outputs["version"]["value"]
        pair = json.loads(SecretManager.payloads[name])
        certificate_key = openssl(["x509", "-pubkey", "-noout"], pair["certificate"])
        private_key = openssl(["pkey", "-pubout"], pair["privateKey"])
        assert certificate_key == private_key, "Certificate and private key differ"
        assert pair["certificate"] == outputs["certificate"]["value"], "Published certificate differs"
        public_cert = root / "public-certificate.pem"
        public_cert.write_text(pair["certificate"])
        result = subprocess.run(["openssl", "verify", "-CAfile", str(public_cert),
                                 "-verify_hostname", "runner.synthetic.internal", str(public_cert)],
                                capture_output=True, timeout=15)
        assert result.returncode == 0, "The published public certificate does not establish hostname trust"
        return name

    def verify_no_private_state():
        blobs = [p.read_bytes() for p in root.glob("*.tfstate*")]
        for plan in root.glob("*.tfplan"):
            with zipfile.ZipFile(plan) as archive:
                blobs.extend(archive.read(name) for name in archive.namelist())
            blobs.append(tf("show", "-json", str(plan)).stdout.encode())
        for blob in blobs:
            assert b"PRIVATE KEY-----" not in blob, "Private key marker in state or plan"
            for value in SecretManager.payloads.values():
                key = json.loads(value)["privateKey"] if value.startswith("{") else value
                for encoded in [key, json.dumps(key)[1:-1], base64.b64encode(key.encode()).decode()]:
                    assert encoded.encode() not in blob, "Private key material in state or plan"
        state = json.loads((root / "terraform.tfstate").read_text())
        for resource in state["resources"]:
            assert resource["mode"] == "managed", "Ephemeral resource persisted in state"
            for instance in resource["instances"]:
                for name in ["secret_data", "secret_data_wo", "private_key_pem", "private_key_pem_wo"]:
                    assert instance["attributes"].get(name) in (None, ""), f"Unexpected persisted {name}"

    try:
        write_config()
        tf("init", "-input=false", "-no-color")
        tf("plan", "-out=initial.tfplan", "-input=false", "-no-color")
        SecretManager.fail_pair = True
        failed = tf("apply", "-input=false", "-no-color", "initial.tfplan", allowed=(1,))
        assert "Injected pair write failure" in failed.stderr, "Initial failure did not reach the pair write"
        verify_no_private_state()
        failed_state = json.loads((root / "terraform.tfstate").read_text())
        issued_certificate = next(resource["instances"][0]["attributes"]["cert_pem"]
                                  for resource in failed_state["resources"]
                                  if resource["type"] == "tls_self_signed_cert")
        SecretManager.fail_pair = False
        tf("apply", "-auto-approve", "-input=false", "-no-color")
        pair_name = verify_pair()
        assert pair_name.endswith("/runner-internal-llm-tls/versions/1")
        pair = json.loads(SecretManager.payloads[pair_name])
        assert pair["certificate"] == issued_certificate, "Retry replaced an already-issued certificate"
        assert pair["privateKey"] == SecretManager.payloads["projects/synthetic-project/secrets/runner-internal-llm-key/versions/1"]
        assert "projects/synthetic-project/secrets/runner-internal-llm-key/versions/2" not in SecretManager.records
        for suffix in ["key", "tls"]:
            secret = SecretManager.records[f"projects/synthetic-project/secrets/runner-internal-llm-{suffix}"]
            assert secret["replication"] == {"automatic": {}}, "Expected automatic replication without CMEK"
        tf("plan", "-detailed-exitcode", "-out=unchanged.tfplan", "-input=false", "-no-color")
        verify_no_private_state()
        print("PASS: interrupted initial saved-plan apply, retry, unchanged plan, private-state exclusion", flush=True)

        SecretManager.fail_pair = True
        replace = "-replace=google_secret_manager_secret_version.internal_runner_tls[0]"
        failed = tf("apply", "-auto-approve", "-input=false", "-no-color", replace, allowed=(1,))
        assert "Injected pair write failure" in failed.stderr, "Replacement failure did not reach the pair write"
        verify_no_private_state()
        SecretManager.fail_pair = False
        tf("apply", "-auto-approve", "-input=false", "-no-color", replace)
        assert verify_pair().endswith("/runner-internal-llm-tls/versions/2")
        print("PASS: interrupted pair replacement and retry preserve the matching identity", flush=True)

        write_config(generation=2)
        tf("plan", "-out=rotation.tfplan", "-input=false", "-no-color")
        tf("apply", "-input=false", "-no-color", "rotation.tfplan")
        assert verify_pair().endswith("/runner-internal-llm-tls/versions/3")
        keys = SecretManager.payloads
        assert keys["projects/synthetic-project/secrets/runner-internal-llm-key/versions/1"] != keys["projects/synthetic-project/secrets/runner-internal-llm-key/versions/2"]
        tf("plan", "-detailed-exitcode", "-input=false", "-no-color")
        verify_no_private_state()
        assert all(record["state"] == "ENABLED" for name, record in SecretManager.records.items()
                   if "/versions/" in name), "Rotation disabled an old identity version"
        print("PASS: explicit key rotation and saved-plan apply retain old versions", flush=True)

        kms_key_name = "projects/key-project/locations/us-central1/keyRings/runner/cryptoKeys/secrets"
        write_config(generation=2, prefix="replacement", kms_key_name=kms_key_name)
        tf("apply", "-auto-approve", "-input=false", "-no-color")
        assert verify_pair().endswith("/replacement-internal-llm-tls/versions/1")
        for suffix in ["key", "tls"]:
            secret = SecretManager.records[f"projects/synthetic-project/secrets/replacement-internal-llm-{suffix}"]
            assert secret["replication"].get("automatic") is None, "CMEK must not use automatic replication"
            assert secret["replication"]["userManaged"] == {"replicas": [{
                "location": "us-central1", "customerManagedEncryption": {"kmsKeyName": kms_key_name}
            }]}, "Expected regional CMEK replication on both secrets"
        verify_no_private_state()
        print("PASS: secret replacement resets numbering, replaces the certificate, and configures CMEK", flush=True)
        print(f"PASS: real Google {google_version} and TLS 4.4.0 providers; no live GCP calls or credentials", flush=True)
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
        shutil.rmtree(root)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--google-provider-version", default="7.6.0")
    main(parser.parse_args().google_provider_version)
