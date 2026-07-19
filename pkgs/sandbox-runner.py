"""Sandboxed code-execution runner for Dorothy.

Two lanes:
  POST /run     - sync, no input file, tight limits, for verifying snippets.
  POST /process - async, downloads an input file and runs heavier limits;
                  result is delivered via a callback POST, then served once
                  from GET /result/<token>.

Isolation is provided per-execution by `systemd-run` (DynamicUser + strict
sandboxing), not by this process itself -- this process runs as root only so
it is allowed to create those transient sandboxed units.
"""

import json
import mimetypes
import os
import secrets
import shutil
import subprocess
import sys
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from queue import Queue

LISTEN_ADDR = os.environ.get("SANDBOX_LISTEN_ADDR", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("SANDBOX_LISTEN_PORT", "8686"))
API_KEY_FILE = os.environ["SANDBOX_API_KEY_FILE"]
JOBS_DIR = Path(os.environ.get("SANDBOX_JOBS_DIR", "/var/lib/sandbox-runner/jobs"))
RESULTS_DIR = Path(
    os.environ.get("SANDBOX_RESULTS_DIR", "/var/lib/sandbox-runner/results")
)
# PATH handed to the *sandboxed* subprocess (python/node/ffmpeg/coreutils store
# paths) -- NixOS has no FHS, so this is how `subprocess.run(["ffmpeg", ...])`-
# style PATH lookups resolve inside the sandbox. Hardcoded paths like /bin/sh
# still won't exist in there; that's an accepted limitation.
SANDBOX_PATH = os.environ.get("SANDBOX_PATH", "/run/current-system/sw/bin")

RESULT_TTL_SEC = 1800
LIGHT_MAX_CONCURRENT = 4
LIGHT_SEM = threading.Semaphore(LIGHT_MAX_CONCURRENT)
HEAVY_QUEUE: "Queue[dict]" = Queue()

# systemd-run resolves its entry command against its own default search path,
# not the --setenv=PATH given to the spawned process -- so this has to be an
# absolute store path, unlike everything the sandboxed code itself shells out to
INTERP = {
    "python": os.environ.get("SANDBOX_PYTHON_BIN", "python3"),
    "js": os.environ.get("SANDBOX_NODE_BIN", "node"),
}


def api_key() -> str:
    return Path(API_KEY_FILE).read_text().strip()


def check_auth(handler: BaseHTTPRequestHandler) -> bool:
    got = handler.headers.get("Authorization", "")
    want = f"Bearer {api_key()}"
    return secrets.compare_digest(got, want)


def run_sandboxed(
    code: str,
    language: str,
    *,
    work_dir: str | None,
    timeout: int,
    memory: str,
    cpu_quota: str,
) -> dict:
    interp = INTERP[language]
    flag = "-c" if language == "python" else "-e"
    cmd = [
        "systemd-run",
        "--wait",
        "--pipe",
        "--collect",
        "--property=DynamicUser=yes",
        "--property=PrivateNetwork=yes",
        "--property=PrivateTmp=yes",
        "--property=ProtectSystem=strict",
        "--property=ProtectHome=yes",
        "--property=NoNewPrivileges=yes",
        f"--property=MemoryMax={memory}",
        f"--property=CPUQuota={cpu_quota}",
        f"--property=RuntimeMaxSec={timeout}",
        f"--setenv=PATH={SANDBOX_PATH}",
    ]
    if work_dir:
        cmd += [
            f"--property=BindPaths={work_dir}:/work",
            "--property=WorkingDirectory=/work",
        ]
    cmd += ["--", interp, flag, code]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout + 10)
    except subprocess.TimeoutExpired:
        return {"stdout": "", "stderr": "", "exit_code": -1, "timed_out": True}
    return {
        "stdout": proc.stdout[-20_000:],
        "stderr": proc.stderr[-20_000:],
        "exit_code": proc.returncode,
        "timed_out": False,
    }


def handle_run(body: dict) -> tuple[int, dict]:
    code = body.get("code")
    language = body.get("language")
    if not code or language not in INTERP:
        return 400, {"error": "code and language (python|js) required"}
    with LIGHT_SEM:
        result = run_sandboxed(
            code, language, work_dir=None, timeout=15, memory="512M", cpu_quota="100%"
        )
    return 200, result


def handle_process(body: dict) -> tuple[int, dict]:
    code = body.get("code")
    language = body.get("language")
    input_url = body.get("input_url")
    callback_url = body.get("callback_url")
    callback_meta = body.get("callback_meta", {})
    if not code or language not in INTERP or not input_url or not callback_url:
        return 400, {"error": "code, language, input_url, callback_url required"}
    job_id = secrets.token_urlsafe(16)
    HEAVY_QUEUE.put(
        {
            "job_id": job_id,
            "code": code,
            "language": language,
            "input_url": input_url,
            "callback_url": callback_url,
            "callback_meta": callback_meta,
        }
    )
    return 202, {"job_id": job_id, "status": "queued"}


def heavy_worker_loop() -> None:
    while True:
        job = HEAVY_QUEUE.get()
        try:
            process_job(job)
        except Exception as e:  # noqa: BLE001 - report to callback, don't crash the loop
            deliver_callback(job, {"status": "error", "error": str(e)})
        finally:
            HEAVY_QUEUE.task_done()


def process_job(job: dict) -> None:
    job_dir = JOBS_DIR / job["job_id"]
    job_dir.mkdir(parents=True, exist_ok=True)
    # DynamicUser=yes picks a random unprivileged uid we can't know ahead of
    # time, and this directory is owned by root (the sandbox-runner process) --
    # without this the sandboxed code can read /work/input but can't write
    # /work/output.* (PermissionError)
    job_dir.chmod(0o777)
    try:
        input_path = job_dir / "input"
        urllib.request.urlretrieve(job["input_url"], input_path)  # noqa: S310 - fixed https CDN
        result = run_sandboxed(
            job["code"],
            job["language"],
            work_dir=str(job_dir),
            timeout=300,
            memory="4G",
            cpu_quota="400%",
        )
        if result.get("timed_out") or result.get("exit_code") not in (0, None):
            deliver_callback(
                job,
                {
                    "status": "error",
                    "stdout": result.get("stdout", ""),
                    "stderr": result.get("stderr", ""),
                    "timed_out": result.get("timed_out", False),
                },
            )
            return
        # the sandboxed code names its own output (output.png, output.mp4, ...)
        # so we can tell Telegram what kind of file it is
        output_matches = sorted(job_dir.glob("output.*"))
        if not output_matches:
            deliver_callback(
                job,
                {
                    "status": "error",
                    "error": "job finished but produced no /work/output.<ext> file",
                    "stdout": result.get("stdout", ""),
                    "stderr": result.get("stderr", ""),
                },
            )
            return
        output_path = output_matches[0]
        mime_type = mimetypes.guess_type(output_path.name)[0] or "application/octet-stream"
        token = secrets.token_urlsafe(24)
        RESULTS_DIR.mkdir(parents=True, exist_ok=True)
        shutil.move(str(output_path), RESULTS_DIR / token)
        (RESULTS_DIR / f"{token}.expires").write_text(str(time.time() + RESULT_TTL_SEC))
        (RESULTS_DIR / f"{token}.mime").write_text(mime_type)
        deliver_callback(
            job,
            {
                "status": "done",
                "result_url": f"https://exec.s4r.in/result/{token}",
                "mime_type": mime_type,
            },
        )
    finally:
        shutil.rmtree(job_dir, ignore_errors=True)


CALLBACK_RETRY_DELAYS_SEC = (2, 5, 10)


def deliver_callback(job: dict, payload: dict) -> None:
    payload = {
        **payload,
        "job_id": job["job_id"],
        "callback_meta": job["callback_meta"],
    }
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        job["callback_url"],
        data=data,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key()}",
        },
    )
    last_error: Exception | None = None
    for attempt, delay in enumerate((0, *CALLBACK_RETRY_DELAYS_SEC)):
        if delay:
            time.sleep(delay)
        try:
            urllib.request.urlopen(req, timeout=15)  # noqa: S310 - worker-controlled URL
            return
        except Exception as e:  # noqa: BLE001
            last_error = e
            print(
                f"callback delivery attempt {attempt + 1} failed for job "
                f"{job['job_id']}: {e}",
                file=sys.stderr,
            )
    print(
        f"callback delivery permanently failed for job {job['job_id']}: {last_error}",
        file=sys.stderr,
    )


def cleanup_loop() -> None:
    while True:
        time.sleep(60)
        now = time.time()
        for marker in RESULTS_DIR.glob("*.expires"):
            try:
                if float(marker.read_text()) < now:
                    token = marker.name.removesuffix(".expires")
                    (RESULTS_DIR / token).unlink(missing_ok=True)
                    (RESULTS_DIR / f"{token}.mime").unlink(missing_ok=True)
                    marker.unlink(missing_ok=True)
            except Exception:  # noqa: BLE001 - best-effort cleanup
                pass


class Handler(BaseHTTPRequestHandler):
    def _json(self, status: int, obj: dict) -> None:
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self) -> None:
        if not check_auth(self):
            self._json(401, {"error": "unauthorized"})
            return
        length = int(self.headers.get("Content-Length", "0"))
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            self._json(400, {"error": "invalid json"})
            return
        if self.path == "/run":
            status, out = handle_run(body)
        elif self.path == "/process":
            status, out = handle_process(body)
        else:
            status, out = 404, {"error": "not found"}
        self._json(status, out)

    def do_GET(self) -> None:
        # unauthenticated by design: Telegram's servers fetch this URL directly,
        # so the unguessable token *is* the auth.
        if not self.path.startswith("/result/"):
            self._json(404, {"error": "not found"})
            return
        token = self.path.removeprefix("/result/")
        if "/" in token or not token:
            self._json(400, {"error": "bad token"})
            return
        path = RESULTS_DIR / token
        if not path.is_file():
            self._json(404, {"error": "not found or expired"})
            return
        mime_marker = RESULTS_DIR / f"{token}.mime"
        mime_type = mime_marker.read_text().strip() if mime_marker.is_file() else "application/octet-stream"
        self.send_response(200)
        self.send_header("Content-Type", mime_type)
        self.send_header("Content-Length", str(path.stat().st_size))
        self.end_headers()
        with path.open("rb") as f:
            shutil.copyfileobj(f, self.wfile)

    def log_message(self, fmt: str, *args: object) -> None:
        print(f"{self.address_string()} - {fmt % args}", file=sys.stderr)


def main() -> None:
    JOBS_DIR.mkdir(parents=True, exist_ok=True)
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    threading.Thread(target=heavy_worker_loop, daemon=True).start()
    threading.Thread(target=cleanup_loop, daemon=True).start()
    server = ThreadingHTTPServer((LISTEN_ADDR, LISTEN_PORT), Handler)
    print(f"sandbox-runner listening on {LISTEN_ADDR}:{LISTEN_PORT}", file=sys.stderr)
    server.serve_forever()


if __name__ == "__main__":
    main()
