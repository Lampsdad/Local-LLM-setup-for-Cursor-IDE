# shellcheck shell=bash
# ============================================================
#  Find a Python that actually runs, and read KEY=VALUE from it.
#
#  Sets KILN_PY to an interpreter, or leaves it empty. Every
#  caller degrades when it is empty rather than failing, so the
#  repo still works on a machine that has weights but no Python.
#
#  Two traps this exists to avoid, both of which fail SILENTLY --
#  the command appears to run and simply produces nothing, so the
#  caller falls back and never says why:
#
#   1. `command -v python3` is not proof of a Python. On Windows
#      (Git Bash, MSYS, WSL interop) it commonly resolves to
#      %LOCALAPPDATA%\Microsoft\WindowsApps\python3.exe -- the
#      Store "App Execution Alias" stub, which exits 0, prints
#      nothing, and opens the Store when run interactively. So
#      run something trivial and check it answers.
#
#   2. Python on Windows writes "\r\n" in text mode. Read with
#      IFS='=' the CR lands at the END OF THE VALUE, so V_MTP
#      becomes $'1\r' and every [ "$V_MTP" = "1" ] test is false
#      while `echo` still prints something that looks like "1".
#      kiln_read_kv strips it.
# ============================================================

KILN_PY=""
for _kp in python3 python py; do
    if command -v "$_kp" >/dev/null 2>&1 &&
       "$_kp" -c "import sys" >/dev/null 2>&1; then
        KILN_PY="$(command -v "$_kp")"
        break
    fi
done
unset _kp

# kiln_read_kv VAR_PREFIX_FILTER... < stream
# Not used directly; callers run their own case filters. This is
# the shared sanitiser they pipe through.
kiln_strip_cr() {
    tr -d '\r'
}
