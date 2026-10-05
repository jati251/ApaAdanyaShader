# Third-party code

## AMD FidelityFX Super Resolution 1

`shaders/lib/vendor/fsr1/fsr1_fp32.glsl` adapts the FP32 EASU and RCAS sections of AMD's `ffx-fsr/ffx_fsr1.h`, version v1.20210629, and its scalar reciprocal/reciprocal-square-root approximations from `ffx-fsr/ffx_a.h`.

Source: https://github.com/GPUOpen-Effects/FidelityFX-FSR

Copyright (c) 2021 Advanced Micro Devices, Inc. All rights reserved.

Licensed under the MIT license reproduced at the top of the adapted source. Changes: GLSL 330 type/function bridge; only FP32 EASU/RCAS retained; unused packed-half RCAS configuration omitted; texture gathers emulated by clamped texel fetches in `program/upscale.fsh`; RCAS callbacks clamp at image borders. The algorithm does not use FP16 extensions, compute dispatches or hardware-specific intrinsics.
