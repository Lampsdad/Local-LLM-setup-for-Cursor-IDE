<#
    Size the launch parameters to the machine actually present.

    The tuned values in this repo were developed on an RTX 5090 (32 GB)
    + Ryzen 9 9900X3D. Hardcoding them means anyone on a 16/24 GB card
    OOMs on the first run, so derive them instead.

    Context sizing is arithmetic, not a lookup table:

      KV per token = 16 cached layers x 4 KV heads x 256 head-dim
                     x 2 (K+V) = 32,768 elements
                   = 34,816 bytes at q8_0 (34 bytes per 32-element block)

    Only 16 of Qwen3.8's 64 layers hold a KV cache -- the other 48 are
    GatedDeltaNet and carry a small fixed recurrent state instead. That
    is why the context windows here look implausibly large next to a
    dense transformer of the same size.

    Emits KEY=VALUE lines for a .bat caller to consume.
#>
param(
    [Parameter(Mandatory = $true)][string]$Model,
    [string]$Mtp    = "",
    [string]$Mmproj = "",
    [int]$MaxCtx    = 262144
)

$ErrorActionPreference = "Stop"

function Get-SizeMiB([string]$path) {
    if ($path -and (Test-Path -LiteralPath $path)) {
        return [int]((Get-Item -LiteralPath $path).Length / 1MB)
    }
    return 0
}

# ---- VRAM ---------------------------------------------------------
$vramMiB = 0
try {
    $raw = & nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null
    if ($LASTEXITCODE -eq 0 -and $raw) {
        # Multi-GPU: llama.cpp defaults to the largest single device.
        $vramMiB = ($raw -split "`n" |
                    Where-Object { $_.Trim() -match '^\d+$' } |
                    ForEach-Object { [int]$_.Trim() } |
                    Measure-Object -Maximum).Maximum
    }
} catch {
    $vramMiB = 0
}

# ---- physical cores -----------------------------------------------
$cores = 0
try {
    $cores = (Get-CimInstance Win32_Processor |
              Measure-Object -Property NumberOfCores -Sum).Sum
} catch {
    $cores = 0
}
if (-not $cores -or $cores -lt 1) {
    # Fall back to half the logical count -- SMT pairs are not extra cores.
    $logical = [int]$env:NUMBER_OF_PROCESSORS
    if ($logical -lt 2) { $logical = 2 }
    $cores = [int]($logical / 2)
}
if ($cores -lt 1) { $cores = 1 }

# ---- context window ------------------------------------------------
$weightsMiB = Get-SizeMiB $Model
$mtpMiB     = Get-SizeMiB $Mtp
$mmprojMiB  = Get-SizeMiB $Mmproj

# Fixed costs that do not scale with context length.
$computeBufMiB  = 2048   # at --ubatch-size 1024
$draftKvMiB     = if ($mtpMiB -gt 0) { 512 } else { 0 }
$recurrentMiB   = 160    # 48 GatedDeltaNet layers, fixed-size state
$driverReserve  = 1536   # desktop compositor / driver overhead

# Allocation is not exact: buffers fragment, the compute buffer grows
# with batch shape, and the driver's own footprint moves around. Aiming
# at 100% of the arithmetic budget reliably OOMs.
#
# This comment used to claim 0.85 reproduces the hand-validated 131072
# on a 32 GB card. It does not: with UD-Q5_K_XL + the q8_0 MTP head +
# f16 vision on a 32607 MiB card it yields 114688. 131072 is what
# actually loaded when it was tried by hand, i.e. the 0.85 margin is
# real headroom rather than a fit to that number. Left at 0.85 -- the
# margin is the point, and it is what keeps smaller cards safe.
$safety = 0.85

$ctx    = 0
$probed = 0
if ($vramMiB -gt 0 -and $weightsMiB -gt 0) {
    $probed  = 1
    $freeMiB = $vramMiB - $driverReserve - $weightsMiB - $mtpMiB -
               $mmprojMiB - $computeBufMiB - $draftKvMiB - $recurrentMiB
    if ($freeMiB -gt 0) {
        $bytesPerToken = 34816
        $ctx = [int]((($freeMiB * $safety) * 1MB) / $bytesPerToken)
        # Round down to a whole number of 4096-token blocks.
        $ctx = [int]($ctx / 4096) * 4096
        if ($ctx -gt $MaxCtx) { $ctx = $MaxCtx }
    }
}

# PROBED distinguishes "no GPU information" from "this will not fit",
# which need different advice from the caller.
"PROBED=$probed"
"VRAM_MIB=$vramMiB"
"CORES=$cores"
"CTX=$ctx"
"WEIGHTS_MIB=$weightsMiB"
