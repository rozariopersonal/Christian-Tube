#!/usr/bin/env python3
"""
Pipeline Health Checker & Self-Healing Watchdog
------------------------------------------------
Continuously monitors Ollama LLM, Pass 1 Scripture Scanner, Pass 2 Lexicon Workers,
and Progress Reporter. If any component or the LLM gets stuck or fails, it automatically
restarts the LLM and the entire pipeline.

Features:
  - Multi-tier LLM Health Probes:
      1. Network & API liveness (GET /api/tags, timeout: 10s)
      2. Process liveness (ollama.exe / llama-server.exe)
      3. Stall / Deadlock detection (pipeline idle > stall_timeout + inference probe timeout)
  - Full Automatic Pipeline Self-Healing:
      - Graceful + forceful termination of hung processes (with taskkill /T process tree cleanup)
      - Restarts Ollama server with custom OLLAMA_MODELS="D:\\models"
      - Polls until Ollama is fully responsive
      - Resets stranded in_progress queue jobs back to pending
      - Restarts Pass 1, Pass 2, and Progress Reporter
  - Individual Process Auto-Recovery:
      - If Pass 1 crashes/exits prematurely, restarts Pass 1
      - If Pass 2 crashes/exits, resets stranded jobs and restarts Pass 2
      - If Reporter exits, restarts Reporter
  - Status & Audit Logging:
      - Writes to releases/study/taobvsi/HEALTH_STATUS.json
      - Logs incidents to releases/study/taobvsi/HEALTH_CHECKER.log
"""

import os
import sys
import time
import json
import psutil
import sqlite3
import argparse
import requests
import datetime
import subprocess
from typing import Dict, Any, List, Optional, Tuple

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")

BASE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
STUDY_DIR = os.path.join(BASE_DIR, "releases", "study", "taobvsi")
LOGS_DIR = os.path.join(STUDY_DIR, "logs")
QUEUE_DB = os.path.join(STUDY_DIR, "taobvsi_glossary_queue.sqlite")
HEALTH_STATUS_JSON = os.path.join(STUDY_DIR, "HEALTH_STATUS.json")
HEALTH_LOG_FILE = os.path.join(STUDY_DIR, "HEALTH_CHECKER.log")

OLLAMA_EXE = r"C:\Users\Arul Rozario\AppData\Local\Programs\Ollama\ollama.exe"
OLLAMA_MODELS_PATH = r"D:\models"
OLLAMA_API_URL = "http://localhost:11434"
DEFAULT_MODEL = "gemma4:12b"

PASS1_SCRIPT = os.path.join(BASE_DIR, "tools", "vocab_pipeline", "build_global_bible_queue.py")
PASS2_SCRIPT = os.path.join(BASE_DIR, "tools", "vocab_pipeline", "run_parallel_lexicon_workers.py")
REPORTER_SCRIPT = os.path.join(BASE_DIR, "tools", "vocab_pipeline", "pipeline_progress_reporter.py")

DEFAULT_STALL_TIMEOUT = 900  # 15 minutes without any queue or chapter progress


def log_message(msg: str):
    """Logs message to console and persistent log file."""
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    formatted = f"[{timestamp}] [WATCHDOG] {msg}"
    print(formatted, flush=True)
    try:
        os.makedirs(STUDY_DIR, exist_ok=True)
        with open(HEALTH_LOG_FILE, "a", encoding="utf-8") as f:
            f.write(formatted + "\n")
    except Exception:
        pass


def find_pipeline_processes() -> Dict[str, List[psutil.Process]]:
    """Identifies active processes for all pipeline components."""
    found: Dict[str, List[psutil.Process]] = {
        "ollama": [],
        "pass1": [],
        "pass2": [],
        "reporter": [],
        "watchdog": []
    }
    current_pid = os.getpid()

    for p in psutil.process_iter(["pid", "name", "cmdline"]):
        try:
            pid = p.info.get("pid")
            if pid == current_pid:
                continue

            name = (p.info.get("name") or "").lower()
            cmdline = " ".join(p.info.get("cmdline") or [])

            if name in ("ollama.exe", "llama-server.exe"):
                found["ollama"].append(p)
            elif "build_global_bible_queue.py" in cmdline and name.startswith("python"):
                found["pass1"].append(p)
            elif "run_parallel_lexicon_workers.py" in cmdline and name.startswith("python"):
                found["pass2"].append(p)
            elif "pipeline_progress_reporter.py" in cmdline and name.startswith("python"):
                found["reporter"].append(p)
            elif "pipeline_health_checker.py" in cmdline and name.startswith("python"):
                found["watchdog"].append(p)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass

    return found


def kill_processes(proc_list: List[psutil.Process], timeout: float = 5.0):
    """Terminates and kills a list of processes and their process trees."""
    if not proc_list:
        return

    # First attempt graceful termination
    for p in proc_list:
        try:
            if sys.platform == "win32":
                subprocess.run(["taskkill", "/F", "/T", "/PID", str(p.pid)], capture_output=True)
            else:
                p.terminate()
        except Exception:
            pass

    # Wait for processes to exit
    gone, alive = psutil.wait_procs(proc_list, timeout=timeout)
    for p in alive:
        try:
            p.kill()
        except Exception:
            pass


def check_ollama_api() -> Tuple[bool, str]:
    """Tests Ollama HTTP API liveness."""
    try:
        r = requests.get(f"{OLLAMA_API_URL}/api/tags", timeout=10)
        if r.status_code == 200:
            return True, "Ollama API responsive (200 OK)"
        return False, f"Ollama API returned HTTP {r.status_code}"
    except requests.exceptions.ConnectionError:
        return False, "Ollama connection refused (Server down)"
    except requests.exceptions.Timeout:
        return False, "Ollama API timed out (> 10s)"
    except Exception as e:
        return False, f"Ollama API error: {str(e)}"


def test_ollama_inference(timeout: int = 45) -> Tuple[bool, str]:
    """Lightweight test generation to verify Ollama is not deadlocked."""
    try:
        payload = {
            "model": DEFAULT_MODEL,
            "prompt": "1+1=",
            "stream": False,
            "options": {"num_predict": 1}
        }
        r = requests.post(f"{OLLAMA_API_URL}/api/generate", json=payload, timeout=timeout)
        if r.status_code == 200:
            return True, f"Inference probe passed ({r.elapsed.total_seconds():.1f}s)"
        return False, f"Inference probe returned HTTP {r.status_code}"
    except requests.exceptions.Timeout:
        return False, f"Inference probe timed out (> {timeout}s - deadlocked)"
    except Exception as e:
        return False, f"Inference probe failed: {str(e)}"


def get_pipeline_db_state() -> Dict[str, Any]:
    """Inspects SQLite database for progress timestamps and stranded jobs."""
    state = {
        "pass1_status": "unknown",
        "last_scanned_chapter": None,
        "completed_count": 0,
        "in_progress_count": 0,
        "pending_count": 0,
        "latest_completed_at": None,
    }

    if not os.path.exists(QUEUE_DB):
        return state

    try:
        conn = sqlite3.connect(f"file:{QUEUE_DB}?mode=ro", uri=True)
        c = conn.cursor()
        c.execute("PRAGMA query_only = ON")

        try:
            for k, v in c.execute("SELECT key, value FROM pipeline_control"):
                if k == "pass1_status":
                    state["pass1_status"] = v
                elif k == "last_scanned_chapter":
                    state["last_scanned_chapter"] = v
        except Exception:
            pass

        try:
            c.execute("SELECT status, count(*) FROM lexicon_queue GROUP BY status")
            for st, cnt in c.fetchall():
                if st == "completed":
                    state["completed_count"] = cnt
                elif st == "in_progress":
                    state["in_progress_count"] = cnt
                elif st == "pending":
                    state["pending_count"] = cnt
        except Exception:
            pass

        try:
            c.execute("SELECT MAX(completed_at) FROM lexicon_queue WHERE status = 'completed'")
            row = c.fetchone()
            if row and row[0]:
                state["latest_completed_at"] = row[0]
        except Exception:
            pass

        conn.close()
    except Exception as e:
        log_message(f"Error querying queue DB: {e}")

    return state


def reset_stranded_queue_jobs() -> int:
    """Resets any in_progress jobs back to pending."""
    if not os.path.exists(QUEUE_DB):
        return 0

    try:
        conn = sqlite3.connect(QUEUE_DB, timeout=30.0)
        c = conn.cursor()
        c.execute("UPDATE lexicon_queue SET status = 'pending', worker_id = NULL WHERE status = 'in_progress'")
        affected = c.rowcount
        conn.commit()
        conn.close()
        if affected > 0:
            log_message(f"Reset {affected} stranded in_progress jobs back to 'pending'.")
        return affected
    except Exception as e:
        log_message(f"Error resetting stranded jobs: {e}")
        return 0


def start_ollama_server() -> bool:
    """Launches Ollama server with OLLAMA_MODELS configured."""
    log_message(f"Starting Ollama server via: {OLLAMA_EXE} serve...")
    os.makedirs(LOGS_DIR, exist_ok=True)
    ollama_log = os.path.join(LOGS_DIR, "ollama.log")

    env = dict(os.environ)
    env["OLLAMA_MODELS"] = OLLAMA_MODELS_PATH
    env["OLLAMA_HOST"] = "127.0.0.1:11434"
    env["OLLAMA_KEEP_ALIVE"] = "24h"
    env["OLLAMA_NUM_PARALLEL"] = "3"
    env["OLLAMA_MAX_LOADED_MODELS"] = "1"

    flags = 0
    if sys.platform == "win32":
        flags = subprocess.CREATE_NEW_PROCESS_GROUP | getattr(subprocess, "DETACHED_PROCESS", 0x00000008)

    with open(ollama_log, "a", encoding="utf-8") as out:
        subprocess.Popen(
            [OLLAMA_EXE, "serve"],
            env=env,
            creationflags=flags,
            stdout=out,
            stderr=subprocess.STDOUT
        )

    # Wait up to 30s for Ollama to become ready
    t0 = time.time()
    while time.time() - t0 < 30:
        time.sleep(2)
        alive, _ = check_ollama_api()
        if alive:
            log_message(f"Ollama server started and ready in {time.time() - t0:.1f}s.")
            return True

    log_message("[ERROR] Ollama server failed to become responsive within 30s.")
    return False


def start_pass1() -> bool:
    """Launches Pass 1 Scripture Scanner."""
    log_message("Starting Pass 1 Scripture Scanner (build_global_bible_queue.py)...")
    os.makedirs(LOGS_DIR, exist_ok=True)
    log_path = os.path.join(LOGS_DIR, "pass1.log")

    env = dict(os.environ)
    env["PYTHONIOENCODING"] = "utf-8"
    env["PYTHONUNBUFFERED"] = "1"

    flags = 0
    if sys.platform == "win32":
        flags = subprocess.CREATE_NEW_PROCESS_GROUP | getattr(subprocess, "DETACHED_PROCESS", 0x00000008)

    with open(log_path, "a", encoding="utf-8") as out:
        subprocess.Popen(
            [sys.executable, PASS1_SCRIPT],
            cwd=BASE_DIR,
            env=env,
            creationflags=flags,
            stdout=out,
            stderr=subprocess.STDOUT
        )
    return True


def start_pass2() -> bool:
    """Launches Pass 2 Lexicon Workers."""
    log_message("Starting Pass 2 Lexicon Workers (run_parallel_lexicon_workers.py --batch-size 10 --workers 2)...")
    os.makedirs(LOGS_DIR, exist_ok=True)
    log_path = os.path.join(LOGS_DIR, "pass2.log")

    env = dict(os.environ)
    env["PYTHONIOENCODING"] = "utf-8"
    env["PYTHONUNBUFFERED"] = "1"

    flags = 0
    if sys.platform == "win32":
        flags = subprocess.CREATE_NEW_PROCESS_GROUP | getattr(subprocess, "DETACHED_PROCESS", 0x00000008)

    with open(log_path, "a", encoding="utf-8") as out:
        subprocess.Popen(
            [sys.executable, PASS2_SCRIPT, "--batch-size", "10", "--workers", "2"],
            cwd=BASE_DIR,
            env=env,
            creationflags=flags,
            stdout=out,
            stderr=subprocess.STDOUT
        )
    return True


def start_reporter() -> bool:
    """Launches Progress Reporter."""
    log_message("Starting Progress Reporter (pipeline_progress_reporter.py --interval 60)...")
    os.makedirs(LOGS_DIR, exist_ok=True)
    log_path = os.path.join(LOGS_DIR, "reporter.log")

    env = dict(os.environ)
    env["PYTHONIOENCODING"] = "utf-8"
    env["PYTHONUNBUFFERED"] = "1"

    flags = 0
    if sys.platform == "win32":
        flags = subprocess.CREATE_NEW_PROCESS_GROUP | getattr(subprocess, "DETACHED_PROCESS", 0x00000008)

    with open(log_path, "a", encoding="utf-8") as out:
        subprocess.Popen(
            [sys.executable, REPORTER_SCRIPT, "--interval", "60"],
            cwd=BASE_DIR,
            env=env,
            creationflags=flags,
            stdout=out,
            stderr=subprocess.STDOUT
        )
    return True


def restart_entire_pipeline(reason: str):
    """Gracefully terminates and restarts Ollama and all pipeline components."""
    log_message(f"🚨 TRIGGERING FULL PIPELINE RESTART. Reason: {reason}")

    procs = find_pipeline_processes()

    # 1. Kill pipeline Python workers
    log_message("Terminating existing pipeline workers...")
    kill_processes(procs["pass1"])
    kill_processes(procs["pass2"])
    kill_processes(procs["reporter"])

    # 2. Kill Ollama
    log_message("Terminating Ollama server...")
    kill_processes(procs["ollama"])
    time.sleep(3)  # Allow VRAM and OS sockets to close

    # 3. Clean up DB stranded jobs
    reset_stranded_queue_jobs()

    # 4. Restart Ollama
    ollama_ok = start_ollama_server()
    if not ollama_ok:
        log_message("[FATAL] Could not restart Ollama server! Will retry next check.")
        return False

    time.sleep(2)

    # 5. Restart Pipeline Components
    start_pass1()
    time.sleep(1)
    start_pass2()
    time.sleep(1)
    start_reporter()

    log_message("✅ Full pipeline self-healing restart completed successfully.")
    return True


def save_health_status(
    ollama_status: str,
    pass1_status: str,
    pass2_status: str,
    reporter_status: str,
    restarts_count: int,
    last_reason: Optional[str] = None
):
    """Writes persistent JSON status for UI/reporter consumption."""
    data = {
        "timestamp": datetime.datetime.now().isoformat(),
        "ollama_status": ollama_status,
        "pass1_status": pass1_status,
        "pass2_status": pass2_status,
        "reporter_status": reporter_status,
        "total_restarts": restarts_count,
        "last_restart_reason": last_reason,
    }
    try:
        with open(HEALTH_STATUS_JSON, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
    except Exception:
        pass


def run_health_checker(check_interval: int = 30, stall_timeout: int = DEFAULT_STALL_TIMEOUT, once: bool = False):
    """Main health checker watchdog loop."""
    log_message("=== PIPELINE HEALTH CHECKER & SELF-HEALING WATCHDOG INITIALIZED ===")
    log_message(f"Check Interval: {check_interval}s | Stall Timeout: {stall_timeout}s | Single Shot: {once}")

    total_restarts = 0
    last_restart_reason: Optional[str] = None
    last_known_completed_count = -1
    last_progress_time = time.time()

    while True:
        try:
            procs = find_pipeline_processes()
            db_state = get_pipeline_db_state()

            # Track progress to detect stalls
            current_completed = db_state["completed_count"]
            if current_completed != last_known_completed_count:
                last_known_completed_count = current_completed
                last_progress_time = time.time()

            idle_duration = time.time() - last_progress_time

            # 1. Check Ollama API
            ollama_api_alive, ollama_msg = check_ollama_api()
            ollama_procs_exist = len(procs["ollama"]) > 0

            ollama_status = "healthy" if (ollama_api_alive and ollama_procs_exist) else "down"

            # Check if LLM is dead or down
            if not ollama_api_alive or not ollama_procs_exist:
                last_restart_reason = f"Ollama down: {ollama_msg}"
                total_restarts += 1
                restart_entire_pipeline(last_restart_reason)
                time.sleep(10)
                continue

            # 2. Check for LLM Stall / Freeze
            # If Pass 2 has pending items, but no words completed for > stall_timeout:
            has_pending_work = db_state["pending_count"] > 0 or db_state["in_progress_count"] > 0
            if has_pending_work and idle_duration > stall_timeout:
                # First check if Ollama is actively working (high CPU)
                ollama_cpu = 0.0
                for p in procs["ollama"]:
                    try:
                        ollama_cpu += p.cpu_percent(interval=0.1)
                    except Exception:
                        pass

                if ollama_cpu > 5.0:
                    # Ollama is crunching tokens actively; reset timer
                    last_progress_time = time.time()
                else:
                    log_message(f"[WARN] Pipeline idle for {idle_duration:.0f}s (> {stall_timeout}s) with 0% CPU. Probing Ollama inference...")
                    inf_ok, inf_msg = test_ollama_inference(timeout=120)
                    if not inf_ok:
                        last_restart_reason = f"LLM inference frozen: {inf_msg}"
                        total_restarts += 1
                        restart_entire_pipeline(last_restart_reason)
                        last_progress_time = time.time()
                        time.sleep(10)
                        continue
                    else:
                        log_message(f"Ollama inference is responsive ({inf_msg}). Resetting stranded jobs...")
                        reset_stranded_queue_jobs()
                        last_progress_time = time.time()
                    last_progress_time = time.time()

            # 3. Component Individual Health Checks
            # Pass 1 Check
            pass1_alive = len(procs["pass1"]) > 0
            pass1_finished = db_state["pass1_status"] == "completed"
            pass1_status_str = "completed" if pass1_finished else ("running" if pass1_alive else "down")

            if not pass1_alive and not pass1_finished:
                log_message("[ALERT] Pass 1 Scripture Scanner is down. Restarting Pass 1...")
                start_pass1()

            # Pass 2 Check
            pass2_alive = len(procs["pass2"]) > 0
            pass2_status_str = "running" if pass2_alive else "down"

            if not pass2_alive and db_state["pending_count"] > 0:
                log_message("[ALERT] Pass 2 Lexicon Worker is down. Restarting Pass 2...")
                reset_stranded_queue_jobs()
                start_pass2()

            # Reporter Check
            reporter_alive = len(procs["reporter"]) > 0
            reporter_status_str = "running" if reporter_alive else "down"

            if not reporter_alive:
                log_message("[ALERT] Progress Reporter is down. Restarting Reporter...")
                start_reporter()

            # Save state
            save_health_status(
                ollama_status=ollama_status,
                pass1_status=pass1_status_str,
                pass2_status=pass2_status_str,
                reporter_status=reporter_status_str,
                restarts_count=total_restarts,
                last_reason=last_restart_reason
            )

        except Exception as e:
            log_message(f"[ERROR] Exception in health check loop: {e}")
            import traceback
            traceback.print_exc()

        if once:
            break

        time.sleep(check_interval)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Pipeline Health Checker & Self-Healing Watchdog")
    parser.add_argument("--check-interval", type=int, default=30, help="Seconds between health checks (default: 30s)")
    parser.add_argument("--stall-timeout", type=int, default=DEFAULT_STALL_TIMEOUT, help="Seconds before considering LLM stalled (default: 600s)")
    parser.add_argument("--once", action="store_true", help="Run health check once and exit")
    args = parser.parse_args()

    run_health_checker(check_interval=args.check_interval, stall_timeout=args.stall_timeout, once=args.once)
