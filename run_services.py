import subprocess
import sys
import threading
import time
import os

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
        for line in iter(process.stdout.readline, b''):
            decoded_line = line.decode('utf-8', errors='replace').rstrip()
            print(f"{color}{prefix}{COLOR_RESET} {decoded_line}")
    except Exception as e:
        print(f"{COLOR_RED}[Error reading {prefix}]{COLOR_RESET} {e}")

def run():
    print(f"{COLOR_CYAN}==================================================")
    print("          CORTEX SERVICE ORCHESTRATOR             ")
    print(f"=================================================={COLOR_RESET}\n")
    print("Starting services (Press Ctrl+C to stop all)...")

    processes = []
    
    # 1. Start Frontend (Vite)
    try:
        print(f"{COLOR_BLUE}[Orchestrator] Starting Frontend (npm run dev)...{COLOR_RESET}")
        fe_process = subprocess.Popen(
            ["npm.cmd", "run", "dev"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=1
        )
        processes.append((fe_process, "Frontend", COLOR_BLUE))
    except Exception as e:
        print(f"{COLOR_RED}[Orchestrator] Failed to start Frontend: {e}{COLOR_RESET}")

    # 2. Start Backend
    try:
        print(f"{COLOR_GREEN}[Orchestrator] Starting Backend (Python API)...{COLOR_RESET}")
        # Resolve Python path relative to virtual environment
        python_exe = r".\venv\Scripts\python.exe"
        if not os.path.exists(python_exe):
            # Fallback to system python if venv not found (though venv should be there)
            python_exe = "python"
        
        be_process = subprocess.Popen(
            [python_exe, "main.py"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=1
        )
        processes.append((be_process, "Backend ", COLOR_GREEN))
    except Exception as e:
        print(f"{COLOR_RED}[Orchestrator] Failed to start Backend: {e}{COLOR_RESET}")

    # 3. Start Ngrok Tunnel
    try:
        print(f"{COLOR_YELLOW}[Orchestrator] Starting Ngrok Tunnel...{COLOR_RESET}")
        ngrok_process = subprocess.Popen(
            ["npx.cmd", "ngrok", "http", "8000", "--config=ngrok.yml", "--url=why-waffle-pentagon.ngrok-free.dev"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=1
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
            bufsize=1
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
            bufsize=1
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

    print(f"\n{COLOR_CYAN}[Orchestrator] All services started. Streaming logs...{COLOR_RESET}\n")

    # Keep main thread alive and monitor for exit
    try:
        while True:
            # Check if any process has exited unexpectedly
            for proc, prefix, color in processes:
                poll = proc.poll()
                if poll is not None:
                    print(f"{COLOR_RED}[Orchestrator] {prefix} exited unexpectedly with code {poll}{COLOR_RESET}")
            time.sleep(2)
    except KeyboardInterrupt:
        print(f"\n\n{COLOR_RED}[Orchestrator] Ctrl+C detected. Stopping all services...{COLOR_RESET}")
        
        # Terminate all processes
        for proc, prefix, color in processes:
            if proc.poll() is None:
                print(f"Stopping {prefix}...")
                proc.terminate()
        
        # Wait a moment for processes to exit gracefully, then force kill if needed
        time.sleep(2)
        for proc, prefix, color in processes:
            if proc.poll() is None:
                print(f"Force-killing {prefix}...")
                proc.kill()
                
        print(f"{COLOR_GREEN}[Orchestrator] Cleanup complete.{COLOR_RESET}")

if __name__ == "__main__":
    run()
