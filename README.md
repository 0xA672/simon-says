# Simon Says – GNAT Health Check

[![Zig](https://img.shields.io/badge/Zig-0.16-orange?logo=zig)](https://ziglang.org/)
[![Ada](https://img.shields.io/badge/Ada-GNAT-blue?logo=ada)](https://www.adacore.com/)
[![License](https://img.shields.io/badge/license-BSD%203--Clause-blue)](LICENSE)

A small Zig program that finds your local GNAT Ada toolchain, compiles a tiny
Ada program, and prints a tribute to **Simon J. Wright** – the maintainer who
kept the macOS GNAT builds alive for many years.

## Background

Simon Wright quietly maintained and distributed native macOS GNAT compilers
long before the official AdaCore releases caught up. His builds answered
questions, fixed obscure bugs, and never asked for attention.

This project is a heartbeat check: it compiles a simple Ada program with your
local GNAT and displays the compiler version, target, and build duration – all
while acknowledging Simon's contribution.

## What it does

- Searches for `gnatmake` (via login shell, cache, and common paths).
- Extracts compiler version, target triplet, and Ada library path.
- Compiles `hello_simon.adb` with GNAT and measures the time.
- Prints a thank‑you message together with the build results.

Example output:

```
With GNAT, Simon Wright gave Ada a home on every Apple machine.
...
GNAT Health Check
-----------------
Compiler  : GNAT 16.1.0
Target    : x86_64-pc-linux-gnu
Test unit : hello_simon.adb
Result    : COMPILATION OK
Exit code : 000000000
Duration  : 000001.128s

Ada is alive.
...
```

## Requirements

- [Zig](https://ziglang.org/download/) 0.16 
- A working GNAT installation (e.g., from AdaCore, Homebrew, or Simon's builds)
- macOS, Linux, or any Unix-like system with `bash`

If you don't have GNAT yet:
- **macOS**: `brew install gcc` (GNAT is included) or use the official AdaCore installer.
- **Ubuntu/Debian**: `sudo apt install gnat`
- **Other**: grab a build from [Simon's repository](https://github.com/simonjwright/building-gcc-macos-native) or AdaCore.

## Getting Started

### Clone the repository

```sh
git clone https://github.com/0xA672/simon-says.git
cd simon-says
```

### Build and run

```sh
# Compile the Zig program (single file, no build system required)
zig build-exe simon-says.zig

# Run the health check
./simon-says
```

You should see a compilation of the Ada test unit followed by the tribute
message and health report.

### Optional: make a single binary

If you want to move the binary somewhere else (e.g., `/usr/local/bin`):

```sh
zig build-exe simon-says.zig -O ReleaseSafe
cp simon-says /usr/local/bin/
```

Then you can run it from anywhere with `simon-says`.

## License

This project is distributed under the **BSD 3-Clause License**, in keeping
with Simon Wright's own preference for permissive licensing.

See [LICENSE](LICENSE) for details.

## Acknowledgements

- **Simon J. Wright** – for years of macOS GNAT builds and community support.
  See [building-gcc-macos-native](https://github.com/simonjwright/building-gcc-macos-native).
- The Ada community – for keeping a great language alive.
