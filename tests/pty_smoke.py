#!/usr/bin/env python3
"""PTY-backed smoke test for history capture and ZLE key interactions."""

from __future__ import annotations

import errno
import os
import pathlib
import pty
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
ZSH = shutil.which("zsh") or "/usr/bin/zsh"
ATUIN = shutil.which("atuin")
ATUIN_SESSION = "00000000-0000-4000-8000-000000000001"


class PtyFailure(RuntimeError):
    pass


def read_until(
    fd: int, output: bytearray, needle: bytes, timeout: float = 10.0
) -> None:
    deadline = time.monotonic() + timeout
    while needle not in output:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise PtyFailure(f"timed out waiting for {needle!r}")
        readable, _, _ = select.select([fd], [], [], remaining)
        if not readable:
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError as error:
            if error.errno == errno.EIO:
                break
            raise
        if not chunk:
            break
        output.extend(chunk)
    if needle not in output:
        raise PtyFailure(f"shell exited before emitting {needle!r}")


def drain(fd: int, output: bytearray, duration: float = 0.25) -> None:
    deadline = time.monotonic() + duration
    while time.monotonic() < deadline:
        readable, _, _ = select.select(
            [fd], [], [], max(0.0, deadline - time.monotonic())
        )
        if not readable:
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError as error:
            if error.errno == errno.EIO:
                return
            raise
        if not chunk:
            return
        output.extend(chunk)


def wait_for_file(path: pathlib.Path, needle: bytes, timeout: float = 5.0) -> bytes:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists():
            content = path.read_bytes()
            if needle in content:
                return content
        time.sleep(0.02)
    current = path.read_bytes() if path.exists() else b""
    raise PtyFailure(
        f"timed out waiting for {needle!r} in {path}; current content: {current!r}"
    )


def main() -> int:
    if not os.access(ZSH, os.X_OK):
        raise PtyFailure(f"zsh is not executable: {ZSH}")

    with tempfile.TemporaryDirectory(prefix="mpz-pty-") as temp_name:
        temp = pathlib.Path(temp_name)
        home = temp / "home"
        zdot = temp / "zdot"
        config = temp / "config"
        cache = temp / "cache"
        state = temp / "state"
        data = temp / "data"
        atuin_home = temp / "atuin-home"
        for directory in (home, zdot, config, cache, state, data, atuin_home):
            directory.mkdir(parents=True)
        atuin_config = config / "atuin"
        atuin_config.mkdir()
        (atuin_config / "config.toml").write_text(
            (ROOT / "config" / "atuin" / "config.toml").read_text(encoding="utf-8")
        )
        (zdot / ".zshrc").symlink_to(ROOT / ".zshrc")
        (zdot / ".zshenv").symlink_to(ROOT / ".zshenv")

        shim_dir = temp / "shims"
        shim_dir.mkdir()
        network_log = temp / "network.log"
        for command_name in ("curl", "wget"):
            shim = shim_dir / command_name
            shim.write_text(
                "#!/bin/sh\n"
                f"printf '%s\\n' '{command_name}' >> '{network_log}'\n"
                "exit 127\n"
            )
            shim.chmod(0o755)

        capture_file = temp / "buffer.capture"
        marker_dir = temp / "markers"
        marker_dir.mkdir()
        probe_file = temp / "probe.zsh"
        probe_file.write_text(
            r"""
if (( $+functions[_atuin_search] )); then
  _atuin_search() {
    print -r -- atuin > "$PTY_MARKER_DIR/atuin"
  }
  print -r -- history=atuin > "$PTY_MARKER_DIR/capabilities"
elif (( $+functions[fzf-history-widget] )); then
  fzf-history-widget() {
    print -r -- history > "$PTY_MARKER_DIR/history"
  }
  print -r -- history=fzf > "$PTY_MARKER_DIR/capabilities"
else
  print -r -- history=unbound > "$PTY_MARKER_DIR/capabilities"
fi
if (( $+commands[fzf] && $+functions[fzf-file-widget] )); then
  fzf-file-widget() {
    print -r -- file > "$PTY_MARKER_DIR/file"
  }
  print -r -- file=fzf > "$PTY_MARKER_DIR/capabilities"
else
  print -r -- file=unbound >> "$PTY_MARKER_DIR/capabilities"
fi
if (( $+commands[fzf] && $+functions[fzf-cd-widget] )); then
  fzf-cd-widget() {
    print -r -- cd > "$PTY_MARKER_DIR/cd"
  }
  print -r -- cd=fzf > "$PTY_MARKER_DIR/capabilities"
else
  print -r -- cd=unbound >> "$PTY_MARKER_DIR/capabilities"
fi
if (( $+commands[fzf] && $+functions[fzf-tab-complete] )); then
  fzf-tab-complete() {
    print -r -- tab > "$PTY_MARKER_DIR/tab"
  }
  print -r -- tab=fzf > "$PTY_MARKER_DIR/capabilities"
else
  print -r -- tab=native > "$PTY_MARKER_DIR/capabilities"
fi
_pty_up_probe() {
  print -r -- up > "$PTY_MARKER_DIR/up"
}
zle -N up-line-or-history _pty_up_probe
self-insert() {
  LBUFFER="${LBUFFER}${KEYS}"
  print -r -- "$BUFFER" > "$PTY_CAPTURE_FILE"
}
zle -N self-insert
_mpz_insert_tab_probe() {
  LBUFFER="${LBUFFER}"$'\t'
  print -r -- tab > "$PTY_MARKER_DIR/tab_probe"
}
zle -N _mpz_insert_tab_probe
# Bind the test-only literal-tab widget in every ZLE keymap. The production
# keymap is selected at ZLE startup, and a single `^X^T` binding is easy to miss
# when the runtime inserts into a keymap other than `emacs`.
for keymap in main emacs vicmd viins command; do
  bindkey -M "$keymap" '^X^T' _mpz_insert_tab_probe
done
print -r -- PTY_PROBE_READY
"""
        )

        environment = os.environ.copy()
        environment.update(
            {
                "HOME": str(home),
                "ZDOTDIR": str(zdot),
                "XDG_CONFIG_HOME": str(config),
                "XDG_CACHE_HOME": str(cache),
                "XDG_STATE_HOME": str(state),
                "XDG_DATA_HOME": str(data),
                "ATUIN_HOME": str(atuin_home),
                "PTY_CAPTURE_FILE": str(capture_file),
                "PTY_MARKER_DIR": str(marker_dir),
                "ATUIN_CONFIG_DIR": str(atuin_config),
                "ATUIN_SESSION": ATUIN_SESSION,
                "PATH": f"{shim_dir}:{environment['PATH']}",
                "PTY_NETWORK_LOG": str(network_log),
                "TERM": "xterm-256color",
            }
        )

        pid, fd = pty.fork()
        if pid == 0:
            os.chdir(ROOT)
            os.execve(ZSH, [ZSH, "-il"], environment)

        output = bytearray()
        try:
            os.write(fd, b'print -r -- PTY""_READY\r')
            read_until(fd, output, b"PTY_READY")
            drain(fd, output, 0.2)

            # Instrument ZLE before the privacy checks so the literal-tab probe
            # is registered when the leading-tab command is submitted.
            os.write(fd, f"source {probe_file!s}\r".encode())
            read_until(fd, output, b"PTY_PROBE_READY")
            drain(fd, output, 0.5)

            os.write(fd, b" echo MPZ_SECRET_MARKER\r")
            os.write(fd, b"\x18\x14echo MPZ_TAB_SECRET_MARKER\r")
            wait_for_file(marker_dir / "tab_probe", b"tab")
            drain(fd, output, 0.1)
            os.write(fd, b"echo MPZ_VISIBLE_MARKER\r")
            os.write(fd, b'print -r -- PTY""_SYNC\r')
            read_until(fd, output, b"PTY_SYNC")
            drain(fd, output, 0.5)

            # Exercise each reserved ZLE key. The instrumented implementations
            # prove that the production binding dispatched to its owner.
            capability_text = wait_for_file(
                marker_dir / "capabilities", b"tab="
            ).decode("utf-8")
            capabilities = dict(
                line.split("=", 1)
                for line in capability_text.splitlines()
                if "=" in line
            )

            if capabilities.get("history") == "atuin":
                os.write(fd, b"\x12")  # Ctrl-R: Atuin history
                wait_for_file(marker_dir / "atuin", b"atuin")
                drain(fd, output, 0.1)
            elif capabilities.get("history") == "fzf":
                os.write(fd, b"\x12")  # Ctrl-R: fzf history fallback
                wait_for_file(marker_dir / "history", b"history")
                drain(fd, output, 0.1)

            if capabilities.get("cd") == "fzf":
                os.write(fd, b"\x1bc")  # Alt-C: fzf directory picker
                wait_for_file(marker_dir / "cd", b"cd")
                drain(fd, output, 0.1)

            if capabilities.get("file") == "fzf":
                os.write(fd, b"\x14")  # Ctrl-T: fzf file picker
                wait_for_file(marker_dir / "file", b"file")
                drain(fd, output, 0.1)

            if capabilities.get("tab") == "fzf":
                os.write(fd, b"\t")  # Tab: fzf-tab completion
                wait_for_file(marker_dir / "tab", b"tab")
                drain(fd, output, 0.1)

            # Up must dispatch to the native-history owner.
            os.write(fd, b"\x1b[A")
            wait_for_file(marker_dir / "up", b"up")
            drain(fd, output, 0.1)

            # Question mark must dispatch to native insertion and remain literal.
            capture_file.unlink(missing_ok=True)
            os.write(fd, b"?PTY_QUESTION")
            question_capture = wait_for_file(capture_file, b"?PTY_QUESTION")
            if question_capture.strip() != b"?PTY_QUESTION":
                raise PtyFailure(
                    "question mark did not remain literal in the ZLE buffer"
                )
            os.write(fd, b"\x15")
            drain(fd, output)

            os.write(fd, b"exit\r")
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                try:
                    waited_pid, _status = os.waitpid(pid, os.WNOHANG)
                except ChildProcessError:
                    break
                if waited_pid == pid:
                    pid = 0
                    break
                drain(fd, output, 0.05)
            if pid:
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    os.waitpid(pid, 0)
                except ChildProcessError:
                    pass
                pid = 0
                raise PtyFailure("interactive shell did not exit")
        except PtyFailure as error:
            raise PtyFailure(
                f"{error}; PTY output tail: {bytes(output)[-2000:]!r}"
            ) from error
        finally:
            if pid:
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    os.waitpid(pid, 0)
                except ChildProcessError:
                    pass
            try:
                os.close(fd)
            except OSError:
                pass

        history_path = state / "zsh" / "history"
        history = (
            history_path.read_text(errors="replace") if history_path.exists() else ""
        )
        if "MPZ_SECRET_MARKER" in history:
            raise PtyFailure("leading-space command reached Zsh history")
        if "MPZ_TAB_SECRET_MARKER" in history:
            raise PtyFailure("leading-tab command reached Zsh history")
        if "MPZ_VISIBLE_MARKER" not in history:
            raise PtyFailure("ordinary command is missing from Zsh history")
        if network_log.exists() and network_log.read_text().strip():
            raise PtyFailure("PTY startup invoked a network client")

        if ATUIN is not None:
            atuin_executable = ATUIN
            atuin_environment = os.environ.copy()
            atuin_environment.update(
                {
                    "HOME": str(home),
                    "XDG_CONFIG_HOME": str(config),
                    "XDG_CACHE_HOME": str(cache),
                    "XDG_STATE_HOME": str(state),
                    "XDG_DATA_HOME": str(data),
                    "ATUIN_HOME": str(atuin_home),
                    "ATUIN_CONFIG_DIR": str(atuin_config),
                    "ATUIN_SESSION": ATUIN_SESSION,
                }
            )

            def query_atuin_history() -> str:
                try:
                    atuin_result = subprocess.run(
                        [atuin_executable, "history", "list", "--cmd-only"],
                        env=atuin_environment,
                        capture_output=True,
                        text=True,
                        check=False,
                        timeout=5,
                    )
                except subprocess.TimeoutExpired as error:
                    raise PtyFailure("atuin history query timed out") from error
                if atuin_result.returncode != 0:
                    raise PtyFailure(
                        f"atuin history query failed: {atuin_result.stderr.strip()}"
                    )
                return atuin_result.stdout

            deadline = time.monotonic() + 5.0
            while "MPZ_VISIBLE_MARKER" not in query_atuin_history():
                if time.monotonic() >= deadline:
                    raise PtyFailure("ordinary command is missing from Atuin history")
                time.sleep(0.05)

            # Atuin finalizes history hooks asynchronously. Require a stable
            # privacy window after the visible entry arrives so a delayed hook
            # cannot slip past a single fixed sleep.
            quiet_since = time.monotonic()
            deadline = quiet_since + 5.0
            while time.monotonic() < deadline:
                atuin_history = query_atuin_history()
                if "MPZ_SECRET_MARKER" in atuin_history:
                    raise PtyFailure("leading-space command reached Atuin history")
                if "MPZ_TAB_SECRET_MARKER" in atuin_history:
                    raise PtyFailure(
                        f"leading-tab command reached Atuin history: {atuin_history!r}"
                    )
                if "MPZ_VISIBLE_MARKER" not in atuin_history:
                    quiet_since = time.monotonic()
                elif time.monotonic() - quiet_since >= 0.75:
                    break
                time.sleep(0.1)
            else:
                raise PtyFailure("Atuin history did not reach a stable state")

            final_atuin_history = query_atuin_history()
            if "MPZ_SECRET_MARKER" in final_atuin_history:
                raise PtyFailure("leading-space command reached final Atuin history")
            if "MPZ_TAB_SECRET_MARKER" in final_atuin_history:
                raise PtyFailure("leading-tab command reached final Atuin history")
            if "MPZ_VISIBLE_MARKER" not in final_atuin_history:
                raise PtyFailure("ordinary command is missing from final Atuin history")

    print("ok - PTY history, privacy, and reserved-key interactions")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PtyFailure as error:
        print(f"not ok - {error}", file=sys.stderr)
        raise SystemExit(1)
