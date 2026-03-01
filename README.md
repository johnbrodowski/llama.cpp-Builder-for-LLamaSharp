# llama.cpp Builder for LLamaSharp

A PowerShell script that interactively builds [llama.cpp](https://github.com/ggml-org/llama.cpp) native DLLs for use with [LLamaSharp](https://github.com/SciSharp/LLamaSharp).

Useful when the version of llama.cpp bundled with LLamaSharp doesn't yet support a model you want to use — for example, multimodal models like **LFM2.5-VL** that require a newer build than what the current NuGet package ships with.

---

## Why would I need this?

LLamaSharp ships with pre-built native binaries for a specific llama.cpp version. When a new model architecture is added to llama.cpp (new multimodal support, new quantization types, etc.), LLamaSharp's bundled binaries may lag behind by several releases.

This script lets you build llama.cpp at any commit, tag, or branch and drop the resulting DLLs into your LLamaSharp project to unlock support for newer models — without waiting for an official NuGet update.

---

## Requirements

- **Windows** (x64)
- **Visual Studio** with the **Desktop development with C++** workload installed
- **Git for Windows** — [git-scm.com](https://git-scm.com)
- **CMake** — [cmake.org](https://cmake.org/download) (or install via VS installer)

Optional, only if building with GPU support:
- **CUDA Toolkit** — for NVIDIA GPU acceleration
- **Vulkan SDK** — for Vulkan GPU acceleration (NVIDIA, AMD, Intel)

---

## Usage

1. Drop `Build-LlamaCpp.ps1` into any folder you want to use as your build workspace.
2. Right-click the script and choose **Run with PowerShell**, or run it from a PowerShell terminal.
3. Follow the prompts.

> **First run tip:** If PowerShell blocks execution, run this once in an admin PowerShell window:
> ```powershell
> Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
> ```

---

## What the script does

The script walks you through three choices:

### 1. llama.cpp Version
Enter any commit hash, release tag, or branch name. Examples:
- `8d3b962` — short commit hash
- `b8175` — release tag
- `master` — latest (may be unstable)

Find releases at: https://github.com/ggml-org/llama.cpp/releases

### 2. Library Type
| Option | When to use |
|---|---|
| **Shared (DLL)** | Use with LLamaSharp. Produces `llama.dll`, `ggml.dll`, etc. |
| **Static (.lib)** | Only needed if you're embedding llama.cpp directly in your own C++ project. |

### 3. GPU Backend
| Option | When to use |
|---|---|
| **CPU only** | Works on any machine. No extra dependencies. Fine for small models. |
| **CUDA** | NVIDIA GPU acceleration. Much faster for large models. Requires CUDA Toolkit. |
| **Vulkan** | GPU acceleration for NVIDIA, AMD, or Intel GPUs. No CUDA Toolkit needed. |

After confirming, the script:
- Clones llama.cpp into a `_llama.cpp_src` subfolder (reused on subsequent runs)
- Checks out the version you specified
- Configures and builds with your chosen options
- Copies all output DLLs into a **versioned subfolder** named after your chosen version

Nothing is ever overwritten or deleted automatically.

---

## Output

Each build is saved into its own folder beside the script, named after the version you built:

```
Build-LlamaCpp.ps1
_llama.cpp_src/          ← shared source clone, reused across builds
8d3b962/                 ← output for this specific build
    llama.dll
    ggml.dll
    ggml-cpu.dll
    ...
    build-info.txt       ← records what options were used
b8175/                   ← a different version built later
    llama.dll
    ...
```

This means you can maintain a local library of builds and swap between them easily.

---

## Using the DLLs with LLamaSharp

Copy **all DLLs** from the versioned output folder into your LLamaSharp runtimes directory:

```
YourProject/
  LLama/
    runtimes/
      win-x64/
        native/
          llama.dll      ← copy here
          ggml.dll       ← and all other DLLs
          ggml-cpu.dll
          ...
```

> **Note:** Some older versions of LLamaSharp expect `libllama.dll` instead of `llama.dll`. If LLamaSharp fails to load the library, try renaming `llama.dll` to `libllama.dll`.

---

## Re-running for a new version

Just run the script again and enter a different commit or tag. The source clone is reused (a `git fetch` is run to pull any new commits), and the new build goes into its own folder. Previous builds are untouched.

---

## Troubleshooting

**Visual Studio not detected**
The script tries to auto-detect VS using `vswhere.exe`. If that fails, it will prompt you to enter the path to `vcvars64.bat` manually. You can find it at:
```
C:\Program Files\Microsoft Visual Studio\<version>\<edition>\VC\Auxiliary\Build\vcvars64.bat
```

**CMake configure fails**
Make sure the **Desktop development with C++** workload is installed in Visual Studio, including the CMake tools component.

**Build fails with CUDA errors**
Verify your CUDA Toolkit is installed and matches your GPU driver version. Run `nvcc --version` to confirm.

**LLamaSharp throws `DllNotFoundException` for `llava_shared`**
Your version of LLamaSharp still loads the LLaVA multimodal library separately. The script includes `-DLLAMA_BUILD_EXAMPLES=ON` which builds it. Make sure you're copying all DLLs from the output folder, not just `llama.dll`.

---

## License

MIT — do whatever you want with it.
