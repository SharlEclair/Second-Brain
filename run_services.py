import subprocess
import sys
import threading
import time
import os
import json
from dotenv import load_dotenv, dotenv_values

# Load and merge local environment variables from .env
load_dotenv()
env_vars = os.environ.copy()
env_vars.update({k: v for k, v in dotenv_values().items() if v is not None})
env_vars["PYTHONUNBUFFERED"] = "1"
for k, v in env_vars.items():
    os.environ[k] = v

# Ensure stdout and stderr use UTF-8 encoding to prevent Unicode errors on special characters (e.g. Vite arrow)
try:
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
except AttributeError:
    pass

# Colors for terminal output
COLOR_BLUE = "\033[94m"
COLOR_GREEN = "\033[92m"
COLOR_YELLOW = "\033[93m"
COLOR_RED = "\033[91m"
COLOR_CYAN = "\033[96m"
COLOR_RESET = "\033[0m"

def stream_output(process, prefix, color):
    """Streams output from a process's stdout/stderr and prints it with a prefix."""
    try:
        # Read stdout line by line
        for line in iter(process.stdout.readline, ''):
            print(f"{color}{prefix}{COLOR_RESET} {line.rstrip()}", flush=True)
    except Exception as e:
        print(f"{COLOR_RED}[Error reading {prefix}]{COLOR_RESET} {e}", flush=True)

def ensure_docker_services():
    """Ensures Redis and Neo4j containers are up via docker compose."""
    print(f"{COLOR_YELLOW}[Orchestrator] Starting Docker services (Redis + Neo4j)...{COLOR_RESET}")
    try:
        # Try modern 'docker compose up -d'
        result = subprocess.run(["docker", "compose", "up", "-d"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if result.returncode == 0:
            print(f"{COLOR_GREEN}[Orchestrator] Docker services (Redis & Neo4j) are up and healthy.{COLOR_RESET}")
            return
    except FileNotFoundError:
        pass
    except Exception as e:
        print(f"{COLOR_YELLOW}[Orchestrator] docker compose up failed ({e}), trying docker-compose...{COLOR_RESET}")

    try:
        result = subprocess.run(["docker-compose", "up", "-d"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if result.returncode == 0:
            print(f"{COLOR_GREEN}[Orchestrator] Docker services (Redis & Neo4j) started via docker-compose.{COLOR_RESET}")
            return
        else:
            print(f"{COLOR_RED}[Orchestrator] Failed to start docker services: {result.stderr.strip()}{COLOR_RESET}")
    except FileNotFoundError:
        print(f"{COLOR_RED}[Orchestrator] Docker not found. Please ensure Redis (port 6379) and Neo4j (ports 7474, 7687) are running.{COLOR_RESET}")
    except Exception as e:
        print(f"{COLOR_RED}[Orchestrator] Error starting Docker services: {e}{COLOR_RESET}")

def kill_process_by_port(port):
    """Kills any process listening on the specified port on Windows."""
    try:
        cmd = f"netstat -ano | findstr :{port}"
        output = subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL)
        lines = output.strip().split('\n')
        pids = set()
        for line in lines:
            parts = line.strip().split()
            if len(parts) >= 5 and parts[1].endswith(f":{port}"):
                pids.add(parts[4])
        for pid in pids:
            if pid != "0":
                subprocess.run(f"taskkill /F /PID {pid}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass

def kill_zombie_processes():
    """Kills any orphaned python.exe or node.exe processes running our apps."""
    try:
        # Don't kill all python, but kill uvicorn / celery instances if possible
        pass
    except Exception:
        pass

def main():
    print(f"{COLOR_CYAN}====================================================={COLOR_RESET}")
    print(f"{COLOR_CYAN}        Second Brain - Full Stack Runner            {COLOR_RESET}")
    print(f"{COLOR_CYAN}====================================================={COLOR_RESET}")
    print()

    # Step 0: Ensure Docker services (Redis + Neo4j) are running
    ensure_docker_services()
    print()
    
    # Clean up duplicate processes & ports
    print(f"{COLOR_YELLOW}[Orchestrator] Cleaning up duplicate Celery and Ngrok processes...{COLOR_RESET}")
    for proc_name in ["celery.exe", "ngrok.exe"]:
        try:
            subprocess.run(f"taskkill /F /IM {proc_name} /T", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass
    kill_process_by_port(8000) # Backend API
    kill_process_by_port(5173) # Frontend React (Vite)
    kill_process_by_port(5174) # Secondary Frontend port
    print()
    
    print("Starting services (Press Ctrl+C to stop all)...")

    processes = []
    
    # 1. Start Frontend (Vite)
    try:
        print(f"{COLOR_BLUE}[Orchestrator] Starting Frontend (npm run dev)...{COLOR_RESET}")
        fe_process = subprocess.Popen(
            ["npm.cmd", "run", "dev"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=1,
            text=True,
            encoding='utf-8',
            env=env_vars
        )
        processes.append((fe_process, "Frontend", COLOR_BLUE))
    except Exception as e:
        print(f"{COLOR_RED}[Orchestrator] Failed to start Frontend: {e}{COLOR_RESET}")

    # 2. Start Backend (with unbuffered stdout/stderr)
    try:
        print(f"{COLOR_GREEN}[Orchestrator] Starting Backend (Python API)...{COLOR_RESET}")
        # Resolve Python path relative to virtual environment
        python_exe = r".\venv\Scripts\python.exe"
        if not os.path.exists(python_exe):
            # Fallback to system python if venv not found (though venv should be there)
            python_exe = "python"
        
        be_process = subprocess.Popen(
            [python_exe, "-u", "main.py"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=1,
            text=True,
            encoding='utf-8',
            env=env_vars
        )
        processes.append((be_process, "Backend ", COLOR_GREEN))
    except Exception as e:
        print(f"{COLOR_RED}[Orchestrator] Failed to start Backend: {e}{COLOR_RESET}")

    # 3. Start Ngrok Tunnel (direct authtoken CLI argument)
    try:
        print(f"{COLOR_YELLOW}[Orchestrator] Starting Ngrok Tunnel...{COLOR_RESET}")
        ngrok_token = env_vars.get("NGROK_AUTHTOKEN", "").strip()
        ngrok_cmd = ["npx.cmd", "ngrok", "http", "8000", "--url=why-waffle-pentagon.ngrok-free.dev"]
        if ngrok_token and ngrok_token != "${NGROK_AUTHTOKEN}":
            ngrok_cmd.extend(["--authtoken", ngrok_token])
        else:
            ngrok_cmd.append("--config=ngrok.yml")

        ngrok_process = subprocess.Popen(
            ngrok_cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=1,
            text=True,
            encoding='utf-8',
            env=env_vars
        )
        processes.append((ngrok_process, "Ngrok   ", COLOR_YELLOW))
    except Exception as e:
        print(f"{COLOR_RED}[Orchestrator] Failed to start Ngrok Tunnel: {e}{COLOR_RESET}")

    # 4. Start Celery Worker
    try:
        print(f"{COLOR_CYAN}[Orchestrator] Starting Celery Worker...{COLOR_RESET}")
        celery_exe = r".\venv\Scripts\celery.exe"
        if not os.path.exists(celery_exe):
            celery_exe = "celery"
            
        celery_worker_process = subprocess.Popen(
            [celery_exe, "-A", "api.celery_app.celery_app", "worker", "--loglevel=info", "-P", "solo"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=1,
            text=True,
            encoding='utf-8',
            env=env_vars
        )
        processes.append((celery_worker_process, "CeleryW ", COLOR_CYAN))
    except Exception as e:
        print(f"{COLOR_RED}[Orchestrator] Failed to start Celery Worker: {e}{COLOR_RESET}")

    # 5. Start Celery Beat
    try:
        print(f"{COLOR_CYAN}[Orchestrator] Starting Celery Beat Scheduler...{COLOR_RESET}")
        celery_exe = r".\venv\Scripts\celery.exe"
        if not os.path.exists(celery_exe):
            celery_exe = "celery"
            
        celery_beat_process = subprocess.Popen(
            [celery_exe, "-A", "api.celery_app.celery_app", "beat", "--loglevel=info"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=1,
            text=True,
            encoding='utf-8',
            env=env_vars
        )
        processes.append((celery_beat_process, "CeleryB ", COLOR_BLUE))
    except Exception as e:
        print(f"{COLOR_RED}[Orchestrator] Failed to start Celery Beat: {e}{COLOR_RESET}")

    # Start monitor threads
    threads = []
    for proc, prefix, color in processes:
        t = threading.Thread(target=stream_output, args=(proc, f"[{prefix}]", color), daemon=True)
        t.start()
        threads.append(t)

    # Monitor processes
    try:
        while True:
            for proc, prefix, _ in processes:
                poll = proc.poll()
                if poll is not None:
                    print(f"{COLOR_RED}[Orchestrator] {prefix} exited unexpectedly with code {poll}{COLOR_RESET}")
                    # If any process dies, trigger shutdown
                    raise KeyboardInterrupt
            time.sleep(1)
    except KeyboardInterrupt:
        print(f"\n{COLOR_YELLOW}[Orchestrator] Shutdown requested. Stopping all services...{COLOR_RESET}")
        
        # Give processes a chance to terminate gracefully
        for proc, prefix, _ in processes:
            print(f"Stopping {prefix}...")
            try:
                proc.terminate()
            except Exception:
                pass
                
        # Speed up cleanup on Windows by killing process trees immediately
        print(f"{COLOR_YELLOW}[Orchestrator] Speeding up cleanup...{COLOR_RESET}")
        kill_zombie_processes()
        kill_process_by_port(8000)
        kill_process_by_port(5173)
        kill_process_by_port(5174)
        
        print(f"{COLOR_GREEN}[Orchestrator] Cleanup complete.{COLOR_RESET}")
        sys.exit(0)

if __name__ == "__main__":
    main()
