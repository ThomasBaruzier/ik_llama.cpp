//
// Copyright (C) 2023-2024 The ggml authors
// Copyright (C) 2024 Iwan Kawrakow
// MIT license
// SPDX-License-Identifier: MIT
//

#import "ggml-metal.h"

#import "ggml-backend-impl.h"
#import "ggml.h"

#import <Foundation/Foundation.h>

#import <Metal/Metal.h>

#undef MIN
#undef MAX
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#define MAX(a, b) ((a) > (b) ? (a) : (b))

#ifdef GGML_METAL_NDEBUG
#define GGML_METAL_LOG_INFO(...)
#define GGML_METAL_LOG_WARN(...)
#define GGML_METAL_LOG_ERROR(...)
#else
#define GGML_METAL_LOG_INFO(...)  ggml_metal_log(GGML_LOG_LEVEL_INFO, __VA_ARGS__)
#define GGML_METAL_LOG_WARN(...)  ggml_metal_log(GGML_LOG_LEVEL_WARN, __VA_ARGS__)
#define GGML_METAL_LOG_ERROR(...) ggml_metal_log(GGML_LOG_LEVEL_ERROR, __VA_ARGS__)
#endif

#define UNUSED(x) (void)(x)

struct ggml_metal_kernel {
    id<MTLComputePipelineState> pipeline;
};

enum ggml_metal_kernel_type {
    GGML_METAL_KERNEL_TYPE_ADD,
    GGML_METAL_KERNEL_TYPE_ADD_4,
    GGML_METAL_KERNEL_TYPE_ADD_ROW,
    GGML_METAL_KERNEL_TYPE_MULTI_ADD,
    GGML_METAL_KERNEL_TYPE_MULTI_ADD_4,
    GGML_METAL_KERNEL_TYPE_MUL,
    GGML_METAL_KERNEL_TYPE_MUL_4,
    GGML_METAL_KERNEL_TYPE_MUL_ROW,
    GGML_METAL_KERNEL_TYPE_DIV,
    GGML_METAL_KERNEL_TYPE_DIV_4,
    GGML_METAL_KERNEL_TYPE_DIV_ROW,
    GGML_METAL_KERNEL_TYPE_REPEAT_F32,
    GGML_METAL_KERNEL_TYPE_REPEAT_F16,
    GGML_METAL_KERNEL_TYPE_REPEAT_I32,
    GGML_METAL_KERNEL_TYPE_REPEAT_I16,
    GGML_METAL_KERNEL_TYPE_SCALE,
    GGML_METAL_KERNEL_TYPE_SCALE_4,
    GGML_METAL_KERNEL_TYPE_SOFTCAP,
    GGML_METAL_KERNEL_TYPE_SOFTCAP_4,
    GGML_METAL_KERNEL_TYPE_CLAMP,
    GGML_METAL_KERNEL_TYPE_TANH,
    GGML_METAL_KERNEL_TYPE_RELU,
    GGML_METAL_KERNEL_TYPE_MUL_RELU,
    GGML_METAL_KERNEL_TYPE_SIGMOID,
    GGML_METAL_KERNEL_TYPE_GELU,
    GGML_METAL_KERNEL_TYPE_GELU_4,
    GGML_METAL_KERNEL_TYPE_MUL_GELU,
    GGML_METAL_KERNEL_TYPE_MUL_GELU_4,
    GGML_METAL_KERNEL_TYPE_GELU_QUICK,
    GGML_METAL_KERNEL_TYPE_GELU_QUICK_4,
    GGML_METAL_KERNEL_TYPE_SILU,
    GGML_METAL_KERNEL_TYPE_SILU_4,
    GGML_METAL_KERNEL_TYPE_MUL_SILU,
    GGML_METAL_KERNEL_TYPE_MUL_SILU_4,
    GGML_METAL_KERNEL_TYPE_SWIGLU,
    GGML_METAL_KERNEL_TYPE_SWIGLU_4,
    GGML_METAL_KERNEL_TYPE_SOFT_MAX_F16,
    GGML_METAL_KERNEL_TYPE_SOFT_MAX_F16_4,
    GGML_METAL_KERNEL_TYPE_SOFT_MAX_F32,
    GGML_METAL_KERNEL_TYPE_SOFT_MAX_F32_4,
    GGML_METAL_KERNEL_TYPE_SOFT_CAP_MAX_F16,
    GGML_METAL_KERNEL_TYPE_SOFT_CAP_MAX_F16_4,
    GGML_METAL_KERNEL_TYPE_SOFT_CAP_MAX_F32,
    GGML_METAL_KERNEL_TYPE_SOFT_CAP_MAX_F32_4,
    GGML_METAL_KERNEL_TYPE_DIAG_MASK_INF,
    GGML_METAL_KERNEL_TYPE_DIAG_MASK_INF_8,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_F32,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_F16,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_Q4_0,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_Q4_1,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_Q5_0,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_Q5_1,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_Q6_0,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_Q8_0,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_Q2_K,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_Q3_K,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_Q4_K,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_Q5_K,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_Q6_K,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ2_XXS,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ2_XS,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ3_XXS,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ3_S,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ2_S,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ1_S,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ1_M,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ1_BN,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ2_BN,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ4_NL,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ4_XS,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ3_KS,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ4_KS,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ5_KS,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ4_KSS,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ2_K,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ2_KS,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ2_KL,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ3_K,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ4_K,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ5_K,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ6_K,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ2_KT,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ3_KT,
    //GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ4_KT,
    GGML_METAL_KERNEL_TYPE_GET_ROWS_I32,
    GGML_METAL_KERNEL_TYPE_RMS_NORM,
    GGML_METAL_KERNEL_TYPE_FUSED_RMS_NORM,
    GGML_METAL_KERNEL_TYPE_GROUP_NORM,
    GGML_METAL_KERNEL_TYPE_NORM,
    GGML_METAL_KERNEL_TYPE_MUL_MV_F32_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_F16_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MV_F16_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_F16_F32_1ROW,
    GGML_METAL_KERNEL_TYPE_MUL_MV_F16_F32_L4,
    GGML_METAL_KERNEL_TYPE_MUL_MV_BF16_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MV_BF16_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_Q4_0_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_Q4_1_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_Q5_0_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_Q5_1_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_Q6_0_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_Q8_0_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_Q2_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_Q3_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_Q4_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_Q5_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_Q6_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_IQ2_XXS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_IQ2_XS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_IQ3_XXS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_IQ3_S_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_IQ2_S_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_IQ1_S_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_IQ1_M_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_IQ1_BN_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_IQ2_BN_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_IQ4_NL_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_IQ4_XS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_IQ3_KS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_IQ4_KS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_IQ4_KSS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_IQ5_KS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_IQ2_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_IQ2_KS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_IQ2_KL_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_IQ3_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_IQ4_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_IQ5_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_IQ6_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_IQ2_KT_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_IQ3_KT_F32,
    //GGML_METAL_KERNEL_TYPE_MUL_MV_IQ4_KT_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_F32_F32,
  //GGML_METAL_KERNEL_TYPE_MUL_MV_ID_F16_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_F16_F32,
  //GGML_METAL_KERNEL_TYPE_MUL_MV_ID_F16_F32_1ROW,
  //GGML_METAL_KERNEL_TYPE_MUL_MV_ID_F16_F32_L4,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_BF16_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q4_0_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q4_1_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q5_0_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q5_1_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q6_0_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q8_0_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q2_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q3_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q4_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q5_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q6_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ2_XXS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ2_XS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ3_XXS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ3_S_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ2_S_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ1_S_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ1_M_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ1_BN_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ2_BN_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ4_NL_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ4_XS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ3_KS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ4_KS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ4_KSS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ5_KS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ2_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ2_KS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ2_KL_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ3_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ4_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ5_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ6_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ2_KT_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ3_KT_F32,
    //GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ4_KT_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_F32_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_F16_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_BF16_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_Q4_0_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_Q4_1_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_Q5_0_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_Q5_1_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_Q6_0_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_Q8_0_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_Q2_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_Q3_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_Q4_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_Q5_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_Q6_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_XXS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_XS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_XXS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_S_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_S_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ1_S_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ1_M_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ1_BN_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_BN_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_NL_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_XS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_KS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_KS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_KSS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ5_KS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_KS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_KL_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ5_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ6_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_KT_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_KT_F32,
    //GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_KT_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_F32_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_F16_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_BF16_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_Q4_0_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_Q4_1_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_Q5_0_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_Q5_1_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_Q6_0_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_Q8_0_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_Q2_K_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_Q3_K_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_Q4_K_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_Q5_K_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_Q6_K_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_XXS_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_XS_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_XXS_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_S_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_S_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ1_S_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ1_M_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ1_BN_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_BN_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_NL_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_XS_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_KS_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_KS_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_KSS_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ5_KS_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_K_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_KS_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_KL_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_K_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_K_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ5_K_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ6_K_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_KT_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_KT_F16,
    //GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_KT_F16,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_F32_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_F16_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_BF16_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q4_0_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q4_1_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q5_0_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q5_1_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q6_0_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q8_0_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q2_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q3_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q4_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q5_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q6_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ2_XXS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ2_XS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ3_XXS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ3_S_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ2_S_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ1_S_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ1_M_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ1_BN_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ2_BN_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ4_NL_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ4_XS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ3_KS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ4_KS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ4_KSS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ5_KS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ2_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ2_KS_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ2_KL_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ3_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ4_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ5_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ6_K_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ2_KT_F32,
    GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ3_KT_F32,
    //GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ4_KT_F32,
    GGML_METAL_KERNEL_TYPE_ROPE_NORM_F32,
    GGML_METAL_KERNEL_TYPE_ROPE_NORM_F16,
    GGML_METAL_KERNEL_TYPE_ROPE_NEOX_F32,
    GGML_METAL_KERNEL_TYPE_ROPE_NEOX_F16,
    GGML_METAL_KERNEL_TYPE_IM2COL_F16,
    GGML_METAL_KERNEL_TYPE_IM2COL_F32,
    GGML_METAL_KERNEL_TYPE_UPSCALE_F32,
    GGML_METAL_KERNEL_TYPE_PAD_F32,
    GGML_METAL_KERNEL_TYPE_ARANGE_F32,
    GGML_METAL_KERNEL_TYPE_TIMESTEP_EMBEDDING_F32,
    GGML_METAL_KERNEL_TYPE_ARGSORT_F32_I32_ASC,
    GGML_METAL_KERNEL_TYPE_ARGSORT_F32_I32_DESC,
    GGML_METAL_KERNEL_TYPE_LEAKY_RELU_F32,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_F16_H64,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_F16_H80,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_F16_H96,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_F16_H112,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_F16_H128,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_F16_H256,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_F16_HK192_HV128,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_F16_HK576_HV512,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_Q8_0_H64,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_Q8_0_H80,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_Q8_0_H96,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_Q8_0_H112,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_Q8_0_H128,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_Q8_0_H256,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_Q8_0_HK192_HV128,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_Q8_0_HK576_HV512,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_F16_H64,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_F16_H80,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_F16_H96,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_F16_H112,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_F16_H128,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_F16_H256,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_F16_HK192_HV128,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_F16_HK576_HV512,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_Q8_0_H64,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_Q8_0_H80,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_Q8_0_H96,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_Q8_0_H112,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_Q8_0_H128,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_Q8_0_H256,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_Q8_0_HK192_HV128,
    GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_Q8_0_HK576_HV512,
    GGML_METAL_KERNEL_TYPE_CPY_F32_F32,
    GGML_METAL_KERNEL_TYPE_CPY_F32_F16,
    GGML_METAL_KERNEL_TYPE_CPY_F16_F16,
    GGML_METAL_KERNEL_TYPE_CPY_F16_F32,
    GGML_METAL_KERNEL_TYPE_CPY_F32_Q8_0,
    GGML_METAL_KERNEL_TYPE_CPY_F32_Q4_0,
    GGML_METAL_KERNEL_TYPE_CPY_F32_Q4_1,
    GGML_METAL_KERNEL_TYPE_CPY_F32_Q5_0,
    GGML_METAL_KERNEL_TYPE_CPY_F32_Q5_1,
    GGML_METAL_KERNEL_TYPE_CPY_F32_Q6_0,
    GGML_METAL_KERNEL_TYPE_CPY_F32_IQ4_NL,
    GGML_METAL_KERNEL_TYPE_CONCAT_F32,
    GGML_METAL_KERNEL_TYPE_CONCAT_F16,
    GGML_METAL_KERNEL_TYPE_SQR,
    GGML_METAL_KERNEL_TYPE_SUM_ROWS,

    GGML_METAL_KERNEL_TYPE_COUNT
};

#define GGML_METAL_MAX_COMMAND_BUFFERS 8

struct ggml_backend_metal_context {

    id<MTLDevice>       device;
    id<MTLCommandQueue> queue;

    dispatch_queue_t d_queue;

    struct ggml_metal_kernel kernels[GGML_METAL_KERNEL_TYPE_COUNT];

    // capture state
    bool capture_next_compute;
    bool capture_started;

    id<MTLCaptureScope> capture_scope;

    // command buffer state
    int n_cb;           // number of extra threads used to submit the command buffers
    int n_nodes_0;      // number of nodes submitted by the main thread
    int n_nodes_1;      // remaining number of nodes submitted by the n_cb threads
    int n_nodes_per_cb;

    struct ggml_cgraph * gf;

    // the callback given to the thread pool
    void (^encode_async)(size_t ith);

    // n_cb command buffers + 1 used by the main thread
    id<MTLCommandBuffer> command_buffers[GGML_METAL_MAX_COMMAND_BUFFERS + 1];

    bool support_simdgroup_reduction;
    bool support_simdgroup_mm;

    bool should_capture_next_compute;

    // abort ggml_metal_graph_compute if callback returns true
    ggml_abort_callback abort_callback;
    void *              abort_callback_data;
};

// MSL code
// TODO: move the contents here when ready
//       for now it is easier to work in a separate file
// static NSString * const msl_library_source = @"see metal.metal";

// Here to assist with NSBundle Path Hack
@interface GGMLMetalClass : NSObject
@end
@implementation GGMLMetalClass
@end

static void ggml_metal_default_log_callback(enum ggml_log_level level, const char * msg, void * user_data) {
    fprintf(stderr, "%s", msg);

    UNUSED(level);
    UNUSED(user_data);
}

ggml_log_callback ggml_metal_log_callback = ggml_metal_default_log_callback;
void * ggml_metal_log_user_data = NULL;

GGML_ATTRIBUTE_FORMAT(2, 3)
static void ggml_metal_log(enum ggml_log_level level, const char * format, ...){
    if (ggml_metal_log_callback != NULL) {
        va_list args;
        va_start(args, format);
        char buffer[128];
        int len = vsnprintf(buffer, 128, format, args);
        if (len < 128) {
            ggml_metal_log_callback(level, buffer, ggml_metal_log_user_data);
        } else {
            char* buffer2 = malloc(len+1);
            va_end(args);
            va_start(args, format);
            vsnprintf(buffer2, len+1, format, args);
            buffer2[len] = 0;
            ggml_metal_log_callback(level, buffer2, ggml_metal_log_user_data);
            free(buffer2);
        }
        va_end(args);
    }
}

static void * ggml_metal_host_malloc(size_t n) {
    void * data = NULL;

#if TARGET_OS_OSX
    kern_return_t err = vm_allocate((vm_map_t) mach_task_self(), (void *) &data, n, VM_FLAGS_ANYWHERE);
    if (err != KERN_SUCCESS) {
        GGML_METAL_LOG_ERROR("%s: error: vm_allocate failed\n", __func__);
        return NULL;
    }
#else
    const int result = posix_memalign((void **) &data, sysconf(_SC_PAGESIZE), n);
    if (result != 0) {
        GGML_METAL_LOG_ERROR("%s: error: posix_memalign failed\n", __func__);
    }
#endif

    return data;
}

static struct ggml_backend_metal_context * ggml_metal_init(int n_cb) {
    GGML_METAL_LOG_INFO("%s: allocating\n", __func__);

#if TARGET_OS_OSX && !GGML_METAL_NDEBUG
    // Show all the Metal device instances in the system
    NSArray * devices = MTLCopyAllDevices();
    for (id<MTLDevice> device in devices) {
        GGML_METAL_LOG_INFO("%s: found device: %s\n", __func__, [[device name] UTF8String]);
    }
    [devices release]; // since it was created by a *Copy* C method
#endif

    // Pick and show default Metal device
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    GGML_METAL_LOG_INFO("%s: picking default device: %s\n", __func__, [[device name] UTF8String]);

    // Configure context
    struct ggml_backend_metal_context * ctx = calloc(1, sizeof(struct ggml_backend_metal_context));
    ctx->device = device;
    ctx->n_cb   = MIN(n_cb, GGML_METAL_MAX_BUFFERS);
    ctx->queue  = [ctx->device newCommandQueue];
    ctx->d_queue = dispatch_queue_create("ggml-metal", DISPATCH_QUEUE_CONCURRENT);

    id<MTLLibrary> metal_library;

    // load library
    //
    // - first check if the library is embedded
    // - then check if the library is in the bundle
    // - if not found, load the source and compile it
    // - if that fails, return NULL
    {
        NSBundle * bundle = nil;
#ifdef SWIFT_PACKAGE
        bundle = SWIFTPM_MODULE_BUNDLE;
#else
        bundle = [NSBundle bundleForClass:[GGMLMetalClass class]];
#endif

        NSError * error = nil;

#if GGML_METAL_EMBED_LIBRARY
        const bool try_metallib = false;
#else
        const bool try_metallib = true;
#endif

        NSString * path_lib = [bundle pathForResource:@"default" ofType:@"metallib"];
        if (try_metallib && path_lib != nil) {
            // pre-compiled library found
            NSURL * libURL = [NSURL fileURLWithPath:path_lib];
            GGML_METAL_LOG_INFO("%s: loading '%s'\n", __func__, [path_lib UTF8String]);

            metal_library = [ctx->device newLibraryWithURL:libURL error:&error];
            if (error) {
                GGML_METAL_LOG_ERROR("%s: error: %s\n", __func__, [[error description] UTF8String]);
                return NULL;
            }
        } else {
#if GGML_METAL_EMBED_LIBRARY
            GGML_METAL_LOG_INFO("%s: using embedded metal library\n", __func__);

            extern const char ggml_metallib_start[];
            extern const char ggml_metallib_end[];

            NSString * src = [[NSString alloc] initWithBytes:ggml_metallib_start length:(ggml_metallib_end-ggml_metallib_start) encoding:NSUTF8StringEncoding];
#else
            GGML_METAL_LOG_INFO("%s: default.metallib not found, loading from source\n", __func__);

            NSString * path_source;
            NSString * path_resource = [[NSProcessInfo processInfo].environment objectForKey:@"GGML_METAL_PATH_RESOURCES"];

            GGML_METAL_LOG_INFO("%s: GGML_METAL_PATH_RESOURCES = %s\n", __func__, path_resource ? [path_resource UTF8String] : "nil");

            if (path_resource) {
                path_source = [path_resource stringByAppendingPathComponent:@"ggml-metal.metal"];
            } else {
                path_source = [bundle pathForResource:@"ggml-metal" ofType:@"metal"];
            }

            if (path_source == nil) {
                GGML_METAL_LOG_WARN("%s: error: could not use bundle path to find ggml-metal.metal, falling back to trying cwd\n", __func__);
                path_source = @"ggml-metal.metal";
            }

            GGML_METAL_LOG_INFO("%s: loading '%s'\n", __func__, [path_source UTF8String]);

            NSString * src = [NSString stringWithContentsOfFile:path_source encoding:NSUTF8StringEncoding error:&error];
            if (error) {
                GGML_METAL_LOG_ERROR("%s: error: %s\n", __func__, [[error description] UTF8String]);
                return NULL;
            }
#endif // GGML_METAL_EMBED_LIBRARY

            @autoreleasepool {
                // dictionary of preprocessor macros
                NSMutableDictionary * prep = [NSMutableDictionary dictionary];

                MTLCompileOptions* options = [MTLCompileOptions new];
                options.preprocessorMacros = prep;

                //[options setFastMathEnabled:false];

                metal_library = [ctx->device newLibraryWithSource:src options:options error:&error];
                if (error) {
                    GGML_METAL_LOG_ERROR("%s: error: %s\n", __func__, [[error description] UTF8String]);
                    return NULL;
                }
            }
        }
    }

    // print MTL GPU family:
    GGML_METAL_LOG_INFO("%s: GPU name:   %s\n", __func__, [[ctx->device name] UTF8String]);

    const NSInteger MTLGPUFamilyMetal3 = 5001;

    // determine max supported GPU family
    // https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf
    // https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf
    {
        for (int i = MTLGPUFamilyApple1 + 20; i >= MTLGPUFamilyApple1; --i) {
            if ([ctx->device supportsFamily:i]) {
                GGML_METAL_LOG_INFO("%s: GPU family: MTLGPUFamilyApple%d  (%d)\n", __func__, i - (int) MTLGPUFamilyApple1 + 1, i);
                break;
            }
        }

        for (int i = MTLGPUFamilyCommon1 + 5; i >= MTLGPUFamilyCommon1; --i) {
            if ([ctx->device supportsFamily:i]) {
                GGML_METAL_LOG_INFO("%s: GPU family: MTLGPUFamilyCommon%d (%d)\n", __func__, i - (int) MTLGPUFamilyCommon1 + 1, i);
                break;
            }
        }

        for (int i = MTLGPUFamilyMetal3 + 5; i >= MTLGPUFamilyMetal3; --i) {
            if ([ctx->device supportsFamily:i]) {
                GGML_METAL_LOG_INFO("%s: GPU family: MTLGPUFamilyMetal%d  (%d)\n", __func__, i - (int) MTLGPUFamilyMetal3 + 3, i);
                break;
            }
        }
    }

    ctx->support_simdgroup_reduction  = [ctx->device supportsFamily:MTLGPUFamilyApple7];
    ctx->support_simdgroup_reduction |= [ctx->device supportsFamily:MTLGPUFamilyMetal3];

    ctx->support_simdgroup_mm = [ctx->device supportsFamily:MTLGPUFamilyApple7];

    GGML_METAL_LOG_INFO("%s: simdgroup reduction support   = %s\n",       __func__, ctx->support_simdgroup_reduction ? "true" : "false");
    GGML_METAL_LOG_INFO("%s: simdgroup matrix mul. support = %s\n",       __func__, ctx->support_simdgroup_mm ? "true" : "false");
    GGML_METAL_LOG_INFO("%s: hasUnifiedMemory              = %s\n",       __func__, ctx->device.hasUnifiedMemory ? "true" : "false");

    ctx->should_capture_next_compute = false;
    ctx->capture_started = false;
    ctx->capture_scope = nil;

    ctx->gf = nil;
    ctx->encode_async = nil;
    for (int i = 0; i < GGML_METAL_MAX_COMMAND_BUFFERS; ++i) {
        ctx->command_buffers[i] = nil;
    }

#if TARGET_OS_OSX || (TARGET_OS_IOS && __clang_major__ >= 15)
    if (@available(macOS 10.12, iOS 16.0, *)) {
        GGML_METAL_LOG_INFO("%s: recommendedMaxWorkingSetSize  = %8.2f MB\n", __func__, ctx->device.recommendedMaxWorkingSetSize / 1e6);
    }
#elif TARGET_OS_OSX
    if (ctx->device.maxTransferRate != 0) {
        GGML_METAL_LOG_INFO("%s: maxTransferRate               = %8.2f MB/s\n", __func__, ctx->device.maxTransferRate / 1e6);
    } else {
        GGML_METAL_LOG_INFO("%s: maxTransferRate               = built-in GPU\n", __func__);
    }
#endif

    // load kernels
    {
        NSError * error = nil;

        for (int i = 0; i < GGML_METAL_KERNEL_TYPE_COUNT; ++i) {
            ctx->kernels[i].pipeline = nil;
        }

        /*
            GGML_METAL_LOG_INFO("%s: loaded %-40s %16p | th_max = %4d | th_width = %4d\n", __func__, "kernel_"#name, (void *) kernel->pipeline, \
                    (int) kernel->pipeline.maxTotalThreadsPerThreadgroup, \
                    (int) kernel->pipeline.threadExecutionWidth); \
        */
#define GGML_METAL_ADD_KERNEL(e, name, supported) \
        if (supported) { \
            struct ggml_metal_kernel * kernel = &ctx->kernels[e]; \
            id<MTLFunction> metal_function = [metal_library newFunctionWithName:@"kernel_"#name]; \
            kernel->pipeline = [ctx->device newComputePipelineStateWithFunction:metal_function error:&error]; \
            [metal_function release]; \
            if (error) { \
                GGML_METAL_LOG_ERROR("%s: error: load pipeline error: %s\n", __func__, [[error description] UTF8String]); \
                [metal_library release]; \
                return NULL; \
            } \
        } else { \
            GGML_METAL_LOG_WARN("%s: skipping %-40s (not supported)\n", __func__, "kernel_"#name); \
        }

        // simd_sum and simd_max requires MTLGPUFamilyApple7

        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_ADD,                           add,                            true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_ADD_4,                         add_4,                          true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_ADD_ROW,                       add_row,                        true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MULTI_ADD,                     multi_add,                      true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MULTI_ADD_4,                   multi_add_4,                    true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL,                           mul,                            true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_4,                         mul_4,                          true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_ROW,                       mul_row,                        true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_DIV,                           div,                            true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_DIV_4,                         div_4,                          true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_DIV_ROW,                       div_row,                        true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_REPEAT_F32,                    repeat_f32,                     true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_REPEAT_F16,                    repeat_f16,                     true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_REPEAT_I32,                    repeat_i32,                     true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_REPEAT_I16,                    repeat_i16,                     true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_SCALE,                         scale,                          true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_SCALE_4,                       scale_4,                        true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_SOFTCAP,                       softcap,                        true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_SOFTCAP_4,                     softcap_4,                      true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_CLAMP,                         clamp,                          true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_TANH,                          tanh,                           true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_RELU,                          relu,                           true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_RELU,                      mul_relu,                       true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_SIGMOID,                       sigmoid,                        true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GELU,                          gelu,                           true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GELU_4,                        gelu_4,                         true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_GELU,                      mul_gelu,                       true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_GELU_4,                    mul_gelu_4,                     true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GELU_QUICK,                    gelu_quick,                     true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GELU_QUICK_4,                  gelu_quick_4,                   true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_SILU,                          silu,                           true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_SILU_4,                        silu_4,                         true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_SILU,                      mul_silu,                       true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_SILU_4,                    mul_silu_4,                     true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_SWIGLU,                        swiglu,                         true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_SWIGLU_4,                      swiglu_4,                       true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_SOFT_MAX_F16,                  soft_max_f16,                   ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_SOFT_MAX_F16_4,                soft_max_f16_4,                 ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_SOFT_MAX_F32,                  soft_max_f32,                   ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_SOFT_MAX_F32_4,                soft_max_f32_4,                 ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_SOFT_CAP_MAX_F16,              soft_cap_max_f16,               ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_SOFT_CAP_MAX_F16_4,            soft_cap_max_f16_4,             ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_SOFT_CAP_MAX_F32,              soft_cap_max_f32,               ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_SOFT_CAP_MAX_F32_4,            soft_cap_max_f32_4,             ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_DIAG_MASK_INF,                 diag_mask_inf,                  true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_DIAG_MASK_INF_8,               diag_mask_inf_8,                true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_F32,                  get_rows_f32,                   true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_F16,                  get_rows_f16,                   true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_Q4_0,                 get_rows_q4_0,                  true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_Q4_1,                 get_rows_q4_1,                  true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_Q5_0,                 get_rows_q5_0,                  true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_Q5_1,                 get_rows_q5_1,                  true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_Q6_0,                 get_rows_q6_0,                  true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_Q8_0,                 get_rows_q8_0,                  true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_Q2_K,                 get_rows_q2_K,                  true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_Q3_K,                 get_rows_q3_K,                  true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_Q4_K,                 get_rows_q4_K,                  true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_Q5_K,                 get_rows_q5_K,                  true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_Q6_K,                 get_rows_q6_K,                  true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ2_XXS,              get_rows_iq2_xxs,               true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ2_XS,               get_rows_iq2_xs,                true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ3_XXS,              get_rows_iq3_xxs,               true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ3_S,                get_rows_iq3_s,                 true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ2_S,                get_rows_iq2_s,                 true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ1_S,                get_rows_iq1_s,                 true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ1_M,                get_rows_iq1_m,                 true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ1_BN,               get_rows_iq1_bn,                true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ2_BN,               get_rows_iq2_bn,                true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ4_NL,               get_rows_iq4_nl,                true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ4_XS,               get_rows_iq4_xs,                true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ3_KS,               get_rows_iq3_ks,                true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ4_KS,               get_rows_iq4_ks,                true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ4_KSS,              get_rows_iq4_kss,               true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ5_KS,               get_rows_iq5_ks,                true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ2_K,                get_rows_iq2_k,                 true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ2_KS,               get_rows_iq2_ks,                true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ2_KL,               get_rows_iq2_kl,                true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ3_K,                get_rows_iq3_k,                 true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ4_K,                get_rows_iq4_k,                 true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ5_K,                get_rows_iq5_k,                 true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ6_K,                get_rows_iq6_k,                 true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ2_KT,               get_rows_iq2_kt,                true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ3_KT,               get_rows_iq3_kt,                true);
        //GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ4_KT,               get_rows_iq4_kt,                true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GET_ROWS_I32,                  get_rows_i32,                   true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_RMS_NORM,                      rms_norm,                       ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FUSED_RMS_NORM,                fused_rms_norm,                 ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_GROUP_NORM,                    group_norm,                     ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_NORM,                          norm,                           true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_F32_F32,                mul_mv_f32_f32,                 ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_F16_F16,                mul_mv_f16_f16,                 ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_F16_F32,                mul_mv_f16_f32,                 ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_F16_F32_1ROW,           mul_mv_f16_f32_1row,            ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_F16_F32_L4,             mul_mv_f16_f32_l4,              ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_BF16_F16,               mul_mv_bf16_f16,                ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_BF16_F32,               mul_mv_bf16_f32,                ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_Q4_0_F32,               mul_mv_q4_0_f32,                ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_Q4_1_F32,               mul_mv_q4_1_f32,                ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_Q5_0_F32,               mul_mv_q5_0_f32,                ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_Q5_1_F32,               mul_mv_q5_1_f32,                ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_Q6_0_F32,               mul_mv_q6_0_f32,                ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_Q8_0_F32,               mul_mv_q8_0_f32,                ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_Q2_K_F32,               mul_mv_q2_K_f32,                ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_Q3_K_F32,               mul_mv_q3_K_f32,                ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_Q4_K_F32,               mul_mv_q4_K_f32,                ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_Q5_K_F32,               mul_mv_q5_K_f32,                ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_Q6_K_F32,               mul_mv_q6_K_f32,                ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_IQ2_XXS_F32,            mul_mv_iq2_xxs_f32,             ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_IQ2_XS_F32,             mul_mv_iq2_xs_f32,              ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_IQ3_XXS_F32,            mul_mv_iq3_xxs_f32,             ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_IQ3_S_F32,              mul_mv_iq3_s_f32,               ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_IQ2_S_F32,              mul_mv_iq2_s_f32,               ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_IQ1_S_F32,              mul_mv_iq1_s_f32,               ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_IQ1_M_F32,              mul_mv_iq1_m_f32,               ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_IQ1_BN_F32,             mul_mv_iq1_bn_f32,              ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_IQ2_BN_F32,             mul_mv_iq2_bn_f32,              ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_IQ4_NL_F32,             mul_mv_iq4_nl_f32,              ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_IQ4_XS_F32,             mul_mv_iq4_xs_f32,              ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_IQ3_KS_F32,             mul_mv_iq3_ks_f32,              ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_IQ4_KS_F32,             mul_mv_iq4_ks_f32,              ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_IQ4_KSS_F32,            mul_mv_iq4_kss_f32,             ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_IQ5_KS_F32,             mul_mv_iq5_ks_f32,              ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_IQ2_K_F32,              mul_mv_iq2_k_f32,               ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_IQ2_KS_F32,             mul_mv_iq2_ks_f32,              ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_IQ2_KL_F32,             mul_mv_iq2_kl_f32,              ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_IQ3_K_F32,              mul_mv_iq3_k_f32,               ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_IQ4_K_F32,              mul_mv_iq4_k_f32,               ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_IQ5_K_F32,              mul_mv_iq5_k_f32,               ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_IQ6_K_F32,              mul_mv_iq6_k_f32,               ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_IQ2_KT_F32,             mul_mv_iq2_kt_f32,              ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_IQ3_KT_F32,             mul_mv_iq3_kt_f32,              ctx->support_simdgroup_reduction);
        //GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_IQ4_KT_F32,             mul_mv_iq4_kt_f32,              ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_F32_F32,             mul_mv_id_f32_f32,              ctx->support_simdgroup_reduction);
      //GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_F16_F16,             mul_mv_id_f16_f16,              ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_F16_F32,             mul_mv_id_f16_f32,              ctx->support_simdgroup_reduction);
      //GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_F16_F32_1ROW,        mul_mv_id_f16_f32_1row,         ctx->support_simdgroup_reduction);
      //GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_F16_F32_L4,          mul_mv_id_f16_f32_l4,           ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_BF16_F32,            mul_mv_id_bf16_f32,             ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q4_0_F32,            mul_mv_id_q4_0_f32,             ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q4_1_F32,            mul_mv_id_q4_1_f32,             ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q5_0_F32,            mul_mv_id_q5_0_f32,             ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q5_1_F32,            mul_mv_id_q5_1_f32,             ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q6_0_F32,            mul_mv_id_q6_0_f32,             ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q8_0_F32,            mul_mv_id_q8_0_f32,             ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q2_K_F32,            mul_mv_id_q2_K_f32,             ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q3_K_F32,            mul_mv_id_q3_K_f32,             ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q4_K_F32,            mul_mv_id_q4_K_f32,             ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q5_K_F32,            mul_mv_id_q5_K_f32,             ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q6_K_F32,            mul_mv_id_q6_K_f32,             ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ2_XXS_F32,         mul_mv_id_iq2_xxs_f32,          ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ2_XS_F32,          mul_mv_id_iq2_xs_f32,           ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ3_XXS_F32,         mul_mv_id_iq3_xxs_f32,          ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ3_S_F32,           mul_mv_id_iq3_s_f32,            ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ2_S_F32,           mul_mv_id_iq2_s_f32,            ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ1_S_F32,           mul_mv_id_iq1_s_f32,            ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ1_M_F32,           mul_mv_id_iq1_m_f32,            ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ1_BN_F32,          mul_mv_id_iq1_bn_f32,           ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ2_BN_F32,          mul_mv_id_iq2_bn_f32,           ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ4_NL_F32,          mul_mv_id_iq4_nl_f32,           ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ4_XS_F32,          mul_mv_id_iq4_xs_f32,           ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ3_KS_F32,          mul_mv_id_iq3_ks_f32,           ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ4_KS_F32,          mul_mv_id_iq4_ks_f32,           ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ4_KSS_F32,         mul_mv_id_iq4_kss_f32,          ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ5_KS_F32,          mul_mv_id_iq5_ks_f32,           ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ2_K_F32,           mul_mv_id_iq2_k_f32,            ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ2_KS_F32,          mul_mv_id_iq2_ks_f32,           ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ2_KL_F32,          mul_mv_id_iq2_kl_f32,           ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ3_K_F32,           mul_mv_id_iq3_k_f32,            ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ4_K_F32,           mul_mv_id_iq4_k_f32,            ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ5_K_F32,           mul_mv_id_iq5_k_f32,            ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ6_K_F32,           mul_mv_id_iq6_k_f32,            ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ2_KT_F32,          mul_mv_id_iq2_kt_f32,           ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ3_KT_F32,          mul_mv_id_iq3_kt_f32,           ctx->support_simdgroup_reduction);
        //GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ4_KT_F32,          mul_mv_id_iq4_kt_f32,           ctx->support_simdgroup_reduction);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_F32_F32,                mul_mm_f32_f32,                 ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_F16_F32,                mul_mm_f16_f32,                 ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_BF16_F32,               mul_mm_bf16_f32,                ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_Q4_0_F32,               mul_mm_q4_0_f32,                ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_Q4_1_F32,               mul_mm_q4_1_f32,                ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_Q5_0_F32,               mul_mm_q5_0_f32,                ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_Q5_1_F32,               mul_mm_q5_1_f32,                ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_Q6_0_F32,               mul_mm_q6_0_f32,                ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_Q8_0_F32,               mul_mm_q8_0_f32,                ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_Q2_K_F32,               mul_mm_q2_K_f32,                ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_Q3_K_F32,               mul_mm_q3_K_f32,                ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_Q4_K_F32,               mul_mm_q4_K_f32,                ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_Q5_K_F32,               mul_mm_q5_K_f32,                ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_Q6_K_F32,               mul_mm_q6_K_f32,                ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_XXS_F32,            mul_mm_iq2_xxs_f32,             ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_XS_F32,             mul_mm_iq2_xs_f32,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_XXS_F32,            mul_mm_iq3_xxs_f32,             ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_S_F32,              mul_mm_iq3_s_f32,               ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_S_F32,              mul_mm_iq2_s_f32,               ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ1_S_F32,              mul_mm_iq1_s_f32,               ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ1_M_F32,              mul_mm_iq1_m_f32,               ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ1_BN_F32,             mul_mm_iq1_bn_f32,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_BN_F32,             mul_mm_iq2_bn_f32,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_NL_F32,             mul_mm_iq4_nl_f32,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_XS_F32,             mul_mm_iq4_xs_f32,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_KS_F32,             mul_mm_iq3_ks_f32,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_KS_F32,             mul_mm_iq4_ks_f32,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_KSS_F32,            mul_mm_iq4_kss_f32,             ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ5_KS_F32,             mul_mm_iq5_ks_f32,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_K_F32,              mul_mm_iq2_k_f32,               ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_KS_F32,             mul_mm_iq2_ks_f32,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_KL_F32,             mul_mm_iq2_kl_f32,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_K_F32,              mul_mm_iq3_k_f32,               ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_K_F32,              mul_mm_iq4_k_f32,               ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ5_K_F32,              mul_mm_iq5_k_f32,               ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ6_K_F32,              mul_mm_iq6_k_f32,               ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_KT_F32,             mul_mm_iq2_kt_f32,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_KT_F32,             mul_mm_iq3_kt_f32,              ctx->support_simdgroup_mm);
        //GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_KT_F32,             mul_mm_iq4_kt_f32,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_F32_F16,                mul_mm_f32_f16,                 ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_F16_F16,                mul_mm_f16_f16,                 ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_BF16_F16,               mul_mm_bf16_f16,                ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_Q4_0_F16,               mul_mm_q4_0_f16,                ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_Q4_1_F16,               mul_mm_q4_1_f16,                ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_Q5_0_F16,               mul_mm_q5_0_f16,                ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_Q5_1_F16,               mul_mm_q5_1_f16,                ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_Q6_0_F16,               mul_mm_q6_0_f16,                ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_Q8_0_F16,               mul_mm_q8_0_f16,                ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_Q2_K_F16,               mul_mm_q2_K_f16,                ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_Q3_K_F16,               mul_mm_q3_K_f16,                ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_Q4_K_F16,               mul_mm_q4_K_f16,                ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_Q5_K_F16,               mul_mm_q5_K_f16,                ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_Q6_K_F16,               mul_mm_q6_K_f16,                ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_XXS_F16,            mul_mm_iq2_xxs_f16,             ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_XS_F16,             mul_mm_iq2_xs_f16,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_XXS_F16,            mul_mm_iq3_xxs_f16,             ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_S_F16,              mul_mm_iq3_s_f16,               ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_S_F16,              mul_mm_iq2_s_f16,               ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ1_S_F16,              mul_mm_iq1_s_f16,               ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ1_M_F16,              mul_mm_iq1_m_f16,               ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ1_BN_F16,             mul_mm_iq1_bn_f16,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_BN_F16,             mul_mm_iq2_bn_f16,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_NL_F16,             mul_mm_iq4_nl_f16,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_XS_F16,             mul_mm_iq4_xs_f16,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_KS_F16,             mul_mm_iq3_ks_f16,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_KS_F16,             mul_mm_iq4_ks_f16,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_KSS_F16,            mul_mm_iq4_kss_f16,             ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ5_KS_F16,             mul_mm_iq5_ks_f16,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_K_F16,              mul_mm_iq2_k_f16,               ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_KS_F16,             mul_mm_iq2_ks_f16,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_KL_F16,             mul_mm_iq2_kl_f16,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_K_F16,              mul_mm_iq3_k_f16,               ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_K_F16,              mul_mm_iq4_k_f16,               ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ5_K_F16,              mul_mm_iq5_k_f16,               ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ6_K_F16,              mul_mm_iq6_k_f16,               ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_KT_F16,             mul_mm_iq2_kt_f16,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_KT_F16,             mul_mm_iq3_kt_f16,              ctx->support_simdgroup_mm);
        //GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_KT_F16,             mul_mm_iq4_kt_f16,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_F32_F32,             mul_mm_id_f32_f32,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_F16_F32,             mul_mm_id_f16_f32,              ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_BF16_F32,            mul_mm_id_bf16_f32,             ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q4_0_F32,            mul_mm_id_q4_0_f32,             ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q4_1_F32,            mul_mm_id_q4_1_f32,             ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q5_0_F32,            mul_mm_id_q5_0_f32,             ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q5_1_F32,            mul_mm_id_q5_1_f32,             ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q6_0_F32,            mul_mm_id_q6_0_f32,             ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q8_0_F32,            mul_mm_id_q8_0_f32,             ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q2_K_F32,            mul_mm_id_q2_K_f32,             ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q3_K_F32,            mul_mm_id_q3_K_f32,             ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q4_K_F32,            mul_mm_id_q4_K_f32,             ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q5_K_F32,            mul_mm_id_q5_K_f32,             ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q6_K_F32,            mul_mm_id_q6_K_f32,             ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ2_XXS_F32,         mul_mm_id_iq2_xxs_f32,          ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ2_XS_F32,          mul_mm_id_iq2_xs_f32,           ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ3_XXS_F32,         mul_mm_id_iq3_xxs_f32,          ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ3_S_F32,           mul_mm_id_iq3_s_f32,            ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ2_S_F32,           mul_mm_id_iq2_s_f32,            ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ1_S_F32,           mul_mm_id_iq1_s_f32,            ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ1_M_F32,           mul_mm_id_iq1_m_f32,            ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ1_BN_F32,          mul_mm_id_iq1_bn_f32,           ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ2_BN_F32,          mul_mm_id_iq2_bn_f32,           ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ4_NL_F32,          mul_mm_id_iq4_nl_f32,           ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ4_XS_F32,          mul_mm_id_iq4_xs_f32,           ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ3_KS_F32,          mul_mm_id_iq3_ks_f32,           ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ4_KS_F32,          mul_mm_id_iq4_ks_f32,           ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ4_KSS_F32,         mul_mm_id_iq4_kss_f32,          ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ5_KS_F32,          mul_mm_id_iq5_ks_f32,           ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ2_K_F32,           mul_mm_id_iq2_k_f32,            ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ2_KS_F32,          mul_mm_id_iq2_ks_f32,           ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ2_KL_F32,          mul_mm_id_iq2_kl_f32,           ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ3_K_F32,           mul_mm_id_iq3_k_f32,            ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ4_K_F32,           mul_mm_id_iq4_k_f32,            ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ5_K_F32,           mul_mm_id_iq5_k_f32,            ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ6_K_F32,           mul_mm_id_iq6_k_f32,            ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ2_KT_F32,          mul_mm_id_iq2_kt_f32,           ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ3_KT_F32,          mul_mm_id_iq3_kt_f32,           ctx->support_simdgroup_mm);
        //GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ4_KT_F32,          mul_mm_id_iq4_kt_f32,           ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_ROPE_NORM_F32,                 rope_norm_f32,                  true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_ROPE_NORM_F16,                 rope_norm_f16,                  true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_ROPE_NEOX_F32,                 rope_neox_f32,                  true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_ROPE_NEOX_F16,                 rope_neox_f16,                  true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_IM2COL_F16,                    im2col_f16,                     true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_IM2COL_F32,                    im2col_f32,                     true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_UPSCALE_F32,                   upscale_f32,                    true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_PAD_F32,                       pad_f32,                        true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_TIMESTEP_EMBEDDING_F32,        timestep_embedding_f32,         true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_ARANGE_F32,                    arange_f32,                     true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_ARGSORT_F32_I32_ASC,           argsort_f32_i32_asc,            true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_ARGSORT_F32_I32_DESC,          argsort_f32_i32_desc,           true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_LEAKY_RELU_F32,                leaky_relu_f32,                 true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_F16_H64,        flash_attn_ext_f16_h64,         ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_F16_H80,        flash_attn_ext_f16_h80,         ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_F16_H96,        flash_attn_ext_f16_h96,         ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_F16_H112,       flash_attn_ext_f16_h112,        ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_F16_H128,       flash_attn_ext_f16_h128,        ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_F16_H256,       flash_attn_ext_f16_h256,        ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_F16_HK192_HV128,flash_attn_ext_f16_hk192_hv128, ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_F16_HK576_HV512,flash_attn_ext_f16_hk576_hv512, ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_Q8_0_H64,        flash_attn_ext_q8_0_h64,         ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_Q8_0_H80,        flash_attn_ext_q8_0_h80,         ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_Q8_0_H96,        flash_attn_ext_q8_0_h96,         ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_Q8_0_H112,       flash_attn_ext_q8_0_h112,        ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_Q8_0_H128,       flash_attn_ext_q8_0_h128,        ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_Q8_0_H256,       flash_attn_ext_q8_0_h256,        ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_Q8_0_HK192_HV128,flash_attn_ext_q8_0_hk192_hv128, ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_Q8_0_HK576_HV512,flash_attn_ext_q8_0_hk576_hv512, ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_F16_H64,        flash_attn_ext_vec_f16_h64,         ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_F16_H80,        flash_attn_ext_vec_f16_h80,         ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_F16_H96,        flash_attn_ext_vec_f16_h96,         ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_F16_H112,       flash_attn_ext_vec_f16_h112,        ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_F16_H128,       flash_attn_ext_vec_f16_h128,        ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_F16_H256,       flash_attn_ext_vec_f16_h256,        ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_F16_HK192_HV128,flash_attn_ext_vec_f16_hk192_hv128, ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_F16_HK576_HV512,flash_attn_ext_vec_f16_hk576_hv512, ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_Q8_0_H64,        flash_attn_ext_vec_q8_0_h64,         ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_Q8_0_H80,        flash_attn_ext_vec_q8_0_h80,         ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_Q8_0_H96,        flash_attn_ext_vec_q8_0_h96,         ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_Q8_0_H112,       flash_attn_ext_vec_q8_0_h112,        ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_Q8_0_H128,       flash_attn_ext_vec_q8_0_h128,        ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_Q8_0_H256,       flash_attn_ext_vec_q8_0_h256,        ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_Q8_0_HK192_HV128,flash_attn_ext_vec_q8_0_hk192_hv128, ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_Q8_0_HK576_HV512,flash_attn_ext_vec_q8_0_hk576_hv512, ctx->support_simdgroup_mm);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_CPY_F32_F16,                   cpy_f32_f16,                    true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_CPY_F32_F32,                   cpy_f32_f32,                    true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_CPY_F16_F16,                   cpy_f16_f16,                    true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_CPY_F16_F32,                   cpy_f16_f32,                    true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_CPY_F32_Q8_0,                  cpy_f32_q8_0,                   true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_CPY_F32_Q4_0,                  cpy_f32_q4_0,                   true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_CPY_F32_Q4_1,                  cpy_f32_q4_1,                   true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_CPY_F32_Q5_0,                  cpy_f32_q5_0,                   true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_CPY_F32_Q5_1,                  cpy_f32_q5_1,                   true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_CPY_F32_Q6_0,                  cpy_f32_q6_0,                   true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_CPY_F32_IQ4_NL,                cpy_f32_iq4_nl,                 true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_CONCAT_F32,                    concat_f32,                     true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_CONCAT_F16,                    concat_f16,                     true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_SQR,                           sqr,                            true);
        GGML_METAL_ADD_KERNEL(GGML_METAL_KERNEL_TYPE_SUM_ROWS,                      sum_rows,                       true);
    }

    [metal_library release];
    return ctx;
}

static void ggml_metal_free(struct ggml_backend_metal_context * ctx) {
    GGML_METAL_LOG_INFO("%s: deallocating\n", __func__);

    for (int i = 0; i < GGML_METAL_KERNEL_TYPE_COUNT; ++i) {
        [ctx->kernels[i].pipeline release];
    }

    Block_release(ctx->encode_async);

    [ctx->queue release];
    [ctx->device release];

    dispatch_release(ctx->d_queue);

    free(ctx);
}

// temporarily defined here for compatibility between ggml-backend and the old API

struct ggml_backend_metal_buffer {
    void   * data;
    size_t   size;

    id<MTLBuffer> metal;
};

struct ggml_backend_metal_buffer_context {
    void * all_data;
    size_t all_size;
    bool owned;

    // multiple buffers are used only to avoid the maximum buffer size limitation when using mmap
    int n_buffers;
    struct ggml_backend_metal_buffer buffers[GGML_METAL_MAX_BUFFERS];
};

// finds the Metal buffer that contains the tensor data on the GPU device
// the assumption is that there is 1-to-1 mapping between the host and device memory buffers, so we can find the
// Metal buffer based on the host memory pointer
//
static id<MTLBuffer> ggml_metal_get_buffer(struct ggml_tensor * t, size_t * offs) {
    //GGML_METAL_LOG_INFO("%s: data tensor '%16s', offs_data = %8ld, offs_eval = %8ld, offs_cach = %8ld\n", __func__, t->name, offs_data, offs_eval, offs_cach);

    const int64_t tsize = ggml_nbytes(t);

    ggml_backend_buffer_t buffer = t->view_src ? t->view_src->buffer : t->buffer;

    struct ggml_backend_metal_buffer_context * buf_ctx = (struct ggml_backend_metal_buffer_context *) buffer->context;

    // find the view that contains the tensor fully
    for (int i = 0; i < buf_ctx->n_buffers; ++i) {
        const int64_t ioffs = (int64_t) t->data - (int64_t) buf_ctx->buffers[i].data;

        //GGML_METAL_LOG_INFO("ioffs = %10ld, tsize = %10ld, sum = %10ld, buf_ctx->buffers[%d].size = %10ld\n", ioffs, tsize, ioffs + tsize, i, buf_ctx->buffers[i].size);
        if (ioffs >= 0 && ioffs + tsize <= (int64_t) buf_ctx->buffers[i].size) {
            *offs = (size_t) ioffs;

            //GGML_METAL_LOG_INFO("%s: tensor '%16s', offs = %8ld\n", __func__, t->name, *offs);

            return buf_ctx->buffers[i].metal;
        }
    }

    GGML_METAL_LOG_ERROR("%s: error: tensor '%s' buffer is nil\n", __func__, t->name);

    return nil;
}

static bool ggml_metal_supports_op(const struct ggml_backend_metal_context * ctx, const struct ggml_tensor * op) {

    for (size_t i = 0, n = 3; i < n; ++i) {
        if (op->src[i] != NULL && op->src[i]->type == GGML_TYPE_BF16) {
            if (op->op != GGML_OP_MUL_MAT && op->op != GGML_OP_MUL_MAT_ID && op->op != GGML_OP_GET_ROWS) {
                return false;
            }
        }
    }

    switch (op->op) {
        case GGML_OP_UNARY:
            switch (ggml_get_unary_op(op)) {
                case GGML_UNARY_OP_TANH:
                case GGML_UNARY_OP_RELU:
                case GGML_UNARY_OP_SIGMOID:
                case GGML_UNARY_OP_GELU:
                case GGML_UNARY_OP_GELU_QUICK:
                case GGML_UNARY_OP_SILU:
                case GGML_UNARY_OP_SWIGLU:
                    return ggml_is_contiguous(op->src[0]);
                default:
                    return false;
            }
        case GGML_OP_NONE:
        case GGML_OP_RESHAPE:
        case GGML_OP_VIEW:
        case GGML_OP_TRANSPOSE:
        case GGML_OP_PERMUTE:
        case GGML_OP_CONCAT:
        case GGML_OP_ADD:
        case GGML_OP_MULTI_ADD:
        case GGML_OP_ACC:
        case GGML_OP_MUL:
        case GGML_OP_DIV:
        case GGML_OP_REPEAT:
        case GGML_OP_SCALE:
        case GGML_OP_CLAMP:
        case GGML_OP_SQR:
        case GGML_OP_SUM_ROWS:
            return true;
        case GGML_OP_FUSED_MUL_UNARY:
            return ggml_is_contiguous(op->src[0]);
        case GGML_OP_SOFTCAP:
        case GGML_OP_SOFT_CAP_MAX:
            return true; //ggml_is_contiguous(op->src[0]) && ggml_is_contiguous(op);
        case GGML_OP_SOFT_MAX:
        case GGML_OP_RMS_NORM:
        case GGML_OP_FUSED_RMS_NORM:
        case GGML_OP_GROUP_NORM:
            return ctx->support_simdgroup_reduction;
        case GGML_OP_NORM:
        case GGML_OP_ROPE:
        case GGML_OP_IM2COL:
            return true;
        case GGML_OP_POOL_1D:
        case GGML_OP_POOL_2D:
            return false;
        case GGML_OP_UPSCALE:
        case GGML_OP_PAD:
        case GGML_OP_ARANGE:
        case GGML_OP_TIMESTEP_EMBEDDING:
        case GGML_OP_ARGSORT:
        case GGML_OP_LEAKY_RELU:
            return true;
        case GGML_OP_FLASH_ATTN_EXT:
            if (!ctx->support_simdgroup_mm) {
                return false; // TODO: over-restricted for vec-kernels
            }
            if (op->src[1]->type != op->src[2]->type ||
               (op->src[1]->type != GGML_TYPE_F16 && op->src[1]->type != GGML_TYPE_Q8_0)) {
                return false;
            }
            if (op->src[1]->ne[0] != op->src[2]->ne[0]) {
                return (op->src[1]->ne[0] == 192 && op->src[2]->ne[0] == 128) ||
                       (op->src[1]->ne[0] == 576 && op->src[2]->ne[0] == 512);
            }
            return (op->src[1]->ne[0] ==  64 || op->src[1]->ne[0] ==  80 ||
                    op->src[1]->ne[0] ==  96 || op->src[1]->ne[0] == 112 ||
                    op->src[1]->ne[0] == 128 || op->src[1]->ne[0] == 256);
        case GGML_OP_MUL_MAT:
            return ctx->support_simdgroup_reduction &&
                (op->src[1]->type == GGML_TYPE_F32 || op->src[1]->type == GGML_TYPE_F16) &&
               !(op->src[0]->type >= GGML_TYPE_Q4_0_R8 && op->src[0]->type <= GGML_TYPE_Q8_K_R8);
        case GGML_OP_MUL_MAT_ID:
            return ctx->support_simdgroup_reduction &&
                (op->src[0]->type != GGML_TYPE_F32 || op->src[1]->type == GGML_TYPE_F32);
        case GGML_OP_CPY:
        case GGML_OP_DUP:
        case GGML_OP_CONT:
            {
                switch (op->src[0]->type) {
                    case GGML_TYPE_F32:
                        switch (op->type) {
                           case GGML_TYPE_F32:
                           case GGML_TYPE_F16:
                           case GGML_TYPE_Q8_0:
                           case GGML_TYPE_Q4_0:
                           case GGML_TYPE_Q4_1:
                           case GGML_TYPE_Q5_0:
                           case GGML_TYPE_Q5_1:
                           case GGML_TYPE_Q6_0:
                           case GGML_TYPE_IQ4_NL:
                                return true;
                           default:
                                return false;
                        }
                    case GGML_TYPE_F16:
                        switch (op->type) {
                           case GGML_TYPE_F32:
                           case GGML_TYPE_F16:
                                return true;
                           default:
                                return false;
                        }
                    default:
                        return false;
                };
            }
        case GGML_OP_DIAG_MASK_INF:
        case GGML_OP_GET_ROWS:
            {
                return op->ne[3] == 1;
            }
        default:
            return false;
    }
}

static void ggml_metal_encode_node(
        struct ggml_backend_metal_context * ctx,
               struct ggml_tensor         * node,
               id<MTLComputeCommandEncoder> encoder) {


    struct ggml_tensor * src0 = node->src[0];
    struct ggml_tensor * src1 = node->src[1];
    struct ggml_tensor * src2 = node->src[2];
    struct ggml_tensor * dst  = node;

    if (ggml_is_empty(dst)) {
        return;
    }

    switch (dst->op) {
        case GGML_OP_NONE:
        case GGML_OP_RESHAPE:
        case GGML_OP_VIEW:
        case GGML_OP_TRANSPOSE:
        case GGML_OP_PERMUTE: return; // noop
        default: break;
    }

    if (!ggml_metal_supports_op(ctx, dst)) {
        GGML_METAL_LOG_ERROR("%s: error: unsupported op '%s'\n", __func__, ggml_op_desc(dst));
        GGML_ABORT("unsupported op");
    }

    const int64_t  ne00 = src0 ? src0->ne[0] : 0;
    const int64_t  ne01 = src0 ? src0->ne[1] : 0;
    const int64_t  ne02 = src0 ? src0->ne[2] : 0;
    const int64_t  ne03 = src0 ? src0->ne[3] : 0;

    const uint64_t nb00 = src0 ? src0->nb[0] : 0;
    const uint64_t nb01 = src0 ? src0->nb[1] : 0;
    const uint64_t nb02 = src0 ? src0->nb[2] : 0;
    const uint64_t nb03 = src0 ? src0->nb[3] : 0;

    const int64_t  ne10 = src1 ? src1->ne[0] : 0;
    const int64_t  ne11 = src1 ? src1->ne[1] : 0;
    const int64_t  ne12 = src1 ? src1->ne[2] : 0;
    const int64_t  ne13 = src1 ? src1->ne[3] : 0;

    const uint64_t nb10 = src1 ? src1->nb[0] : 0;
    const uint64_t nb11 = src1 ? src1->nb[1] : 0;
    const uint64_t nb12 = src1 ? src1->nb[2] : 0;
    const uint64_t nb13 = src1 ? src1->nb[3] : 0;

    const int64_t  ne20 = src2 ? src2->ne[0] : 0;
    const int64_t  ne21 = src2 ? src2->ne[1] : 0;
    const int64_t  ne22 = src2 ? src2->ne[2] : 0; GGML_UNUSED(ne22);
    const int64_t  ne23 = src2 ? src2->ne[3] : 0; GGML_UNUSED(ne23);

    const uint64_t nb20 = src2 ? src2->nb[0] : 0; GGML_UNUSED(nb20);
    const uint64_t nb21 = src2 ? src2->nb[1] : 0;
    const uint64_t nb22 = src2 ? src2->nb[2] : 0;
    const uint64_t nb23 = src2 ? src2->nb[3] : 0;

    const int64_t  ne0  =  dst ?  dst->ne[0] : 0;
    const int64_t  ne1  =  dst ?  dst->ne[1] : 0;
    const int64_t  ne2  =  dst ?  dst->ne[2] : 0;
    const int64_t  ne3  =  dst ?  dst->ne[3] : 0;

    const uint64_t nb0  =  dst ?  dst->nb[0] : 0;
    const uint64_t nb1  =  dst ?  dst->nb[1] : 0;
    const uint64_t nb2  =  dst ?  dst->nb[2] : 0;
    const uint64_t nb3  =  dst ?  dst->nb[3] : 0;

    const enum ggml_type src0t = src0 ? src0->type : GGML_TYPE_COUNT;
    const enum ggml_type src1t = src1 ? src1->type : GGML_TYPE_COUNT;
    const enum ggml_type dstt  = dst  ? dst->type  : GGML_TYPE_COUNT;

    size_t offs_src0 = 0;
    size_t offs_src1 = 0;
    size_t offs_src2 = 0;
    size_t offs_dst  = 0;

    id<MTLBuffer> id_src0 = src0 ? ggml_metal_get_buffer(src0, &offs_src0) : nil;
    id<MTLBuffer> id_src1 = src1 ? ggml_metal_get_buffer(src1, &offs_src1) : nil;
    id<MTLBuffer> id_src2 = src2 ? ggml_metal_get_buffer(src2, &offs_src2) : nil;
    id<MTLBuffer> id_dst  = dst  ? ggml_metal_get_buffer(dst,  &offs_dst)  : nil;

    //GGML_METAL_LOG_INFO("%s: op - %s\n", __func__, ggml_op_name(dst->op));
    //if (src0) {
    //    GGML_METAL_LOG_INFO("%s: src0 - %4s [%5lld, %5lld, %5lld], %d, %s\n", __func__, ggml_type_name(src0t), ne00, ne01, ne02,
    //            ggml_is_contiguous(src0), src0->name);
    //}
    //if (src1) {
    //    GGML_METAL_LOG_INFO("%s: src1 - %4s [%5lld, %5lld, %5lld], %d, %s\n", __func__, ggml_type_name(src1t), ne10, ne11, ne12,
    //            ggml_is_contiguous(src1), src1->name);
    //}
    //if (dst) {
    //    GGML_METAL_LOG_INFO("%s: dst  - %4s [%5lld, %5lld, %5lld], 1, %s\n",  __func__, ggml_type_name(dstt),  ne0,  ne1,  ne2,
    //            dst->name);
    //}

    switch (dst->op) {
        case GGML_OP_CONCAT:
            {
                GGML_ASSERT(src0->type == src1->type && src0->type == dst->type);

                id<MTLComputePipelineState> pipeline;
                if (dst->type == GGML_TYPE_F32) {
                    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_CONCAT_F32].pipeline;
                }
                else if (dst->type == GGML_TYPE_F16) {
                    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_CONCAT_F16].pipeline;
                }
                else {
                    GGML_ABORT("CONCAT not implemented for this type");
                }

                const int32_t dim = ((int32_t *) dst->op_params)[0];

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0 offset:offs_src0 atIndex:0];
                [encoder setBuffer:id_src1 offset:offs_src1 atIndex:1];
                [encoder setBuffer:id_dst  offset:offs_dst  atIndex:2];
                [encoder setBytes:&ne00 length:sizeof(ne00) atIndex:3];
                [encoder setBytes:&ne01 length:sizeof(ne01) atIndex:4];
                [encoder setBytes:&ne02 length:sizeof(ne02) atIndex:5];
                [encoder setBytes:&ne03 length:sizeof(ne03) atIndex:6];
                [encoder setBytes:&nb00 length:sizeof(nb00) atIndex:7];
                [encoder setBytes:&nb01 length:sizeof(nb01) atIndex:8];
                [encoder setBytes:&nb02 length:sizeof(nb02) atIndex:9];
                [encoder setBytes:&nb03 length:sizeof(nb03) atIndex:10];
                [encoder setBytes:&ne10 length:sizeof(ne10) atIndex:11];
                [encoder setBytes:&ne11 length:sizeof(ne11) atIndex:12];
                [encoder setBytes:&ne12 length:sizeof(ne12) atIndex:13];
                [encoder setBytes:&ne13 length:sizeof(ne13) atIndex:14];
                [encoder setBytes:&nb10 length:sizeof(nb10) atIndex:15];
                [encoder setBytes:&nb11 length:sizeof(nb11) atIndex:16];
                [encoder setBytes:&nb12 length:sizeof(nb12) atIndex:17];
                [encoder setBytes:&nb13 length:sizeof(nb13) atIndex:18];
                [encoder setBytes:&ne0  length:sizeof(ne0)  atIndex:19];
                [encoder setBytes:&ne1  length:sizeof(ne1)  atIndex:20];
                [encoder setBytes:&ne2  length:sizeof(ne2)  atIndex:21];
                [encoder setBytes:&ne3  length:sizeof(ne3)  atIndex:22];
                [encoder setBytes:&nb0  length:sizeof(nb0)  atIndex:23];
                [encoder setBytes:&nb1  length:sizeof(nb1)  atIndex:24];
                [encoder setBytes:&nb2  length:sizeof(nb2)  atIndex:25];
                [encoder setBytes:&nb3  length:sizeof(nb3)  atIndex:26];
                [encoder setBytes:&dim  length:sizeof(dim)  atIndex:27];

                const int nth = MIN(1024, ne0);

                [encoder dispatchThreadgroups:MTLSizeMake(ne1, ne2, ne3) threadsPerThreadgroup:MTLSizeMake(nth, 1, 1)];
            } break;
        case GGML_OP_ADD:
        case GGML_OP_MUL:
        case GGML_OP_DIV:
            {
                GGML_ASSERT(src0t == GGML_TYPE_F32);
                GGML_ASSERT(src1t == GGML_TYPE_F32);

                const size_t offs = 0;

                bool bcast_row = false;

                int64_t nb = ne00; // used by the "row" kernels

                id<MTLComputePipelineState> pipeline = nil;

                if (dst->op == GGML_OP_MUL && ggml_nelements(src1) == 1 && ggml_is_contiguous(src0)) {
                    float scale;
                    memcpy(&scale, src1->data, sizeof(float));
                    //printf("Replacing op_mul with op_scale. scale = %g\n", (double)scale);
                    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_SCALE].pipeline;

                    int64_t n = ggml_nelements(dst);

                    if (n % 4 == 0) {
                        n /= 4;
                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_SCALE_4].pipeline;
                    } else {
                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_SCALE].pipeline;
                    }

                    [encoder setComputePipelineState:pipeline];
                    [encoder setBuffer:id_src0   offset:offs_src0 atIndex:0];
                    [encoder setBuffer:id_dst    offset:offs_dst  atIndex:1];
                    [encoder setBytes:&scale length:sizeof(scale) atIndex:2];

                    [encoder dispatchThreadgroups:MTLSizeMake(n, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
                    break;
                }
                else if (ggml_is_contiguous(dst->src[0]) && ggml_is_contiguous(dst->src[1]) && ggml_is_contiguous(dst) &&
                        dst->src[0]->ne[0] == dst->src[1]->ne[0] && dst->src[0]->ne[0] == dst->ne[0] &&
                        dst->src[0]->ne[1] == dst->src[1]->ne[1] && dst->src[0]->ne[1] == dst->ne[1] &&
                        dst->src[0]->ne[2] == dst->src[1]->ne[2] && dst->src[0]->ne[2] == dst->ne[2] &&
                        dst->src[0]->ne[3] == dst->src[1]->ne[3] && ggml_nelements(dst)%4 == 0) {

                    switch (dst->op) {
                        case GGML_OP_ADD: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_ADD_4].pipeline; break;
                        case GGML_OP_MUL: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_4].pipeline; break;
                        case GGML_OP_DIV: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_DIV_4].pipeline; break;
                        default: GGML_ASSERT(false);
                    }

                    int64_t n = ggml_nelements(dst)/4;

                    [encoder setComputePipelineState:pipeline];
                    [encoder setBuffer:id_src0   offset:offs_src0 atIndex:0];
                    [encoder setBuffer:id_src1   offset:offs_src1 atIndex:1];
                    [encoder setBuffer:id_dst    offset:offs_dst  atIndex:2];

                    [encoder dispatchThreadgroups:MTLSizeMake(n, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
                    break;
                }
                else if (ggml_nelements(src1) == ne10 && ggml_is_contiguous(src1) && ne00 % 4 == 0 && ne10 % 4 == 0) {
                    GGML_ASSERT(ggml_is_contiguous(src0));

                    // src1 is a row
                    GGML_ASSERT(ne11 == 1);

                    nb = ne00 / 4;
                    switch (dst->op) {
                        case GGML_OP_ADD: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_ADD_ROW].pipeline; break;
                        case GGML_OP_MUL: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_ROW].pipeline; break;
                        case GGML_OP_DIV: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_DIV_ROW].pipeline; break;
                        default: GGML_ABORT("fatal error");
                    }

                    bcast_row = true;
                } else {
                    switch (dst->op) {
                        case GGML_OP_ADD: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_ADD].pipeline; break;
                        case GGML_OP_MUL: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL].pipeline; break;
                        case GGML_OP_DIV: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_DIV].pipeline; break;
                        default: GGML_ABORT("fatal error");
                    }
                }

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0 offset:offs_src0 atIndex:0];
                [encoder setBuffer:id_src1 offset:offs_src1 atIndex:1];
                [encoder setBuffer:id_dst  offset:offs_dst  atIndex:2];
                [encoder setBytes:&ne00 length:sizeof(ne00) atIndex:3];
                [encoder setBytes:&ne01 length:sizeof(ne01) atIndex:4];
                [encoder setBytes:&ne02 length:sizeof(ne02) atIndex:5];
                [encoder setBytes:&ne03 length:sizeof(ne03) atIndex:6];
                [encoder setBytes:&nb00 length:sizeof(nb00) atIndex:7];
                [encoder setBytes:&nb01 length:sizeof(nb01) atIndex:8];
                [encoder setBytes:&nb02 length:sizeof(nb02) atIndex:9];
                [encoder setBytes:&nb03 length:sizeof(nb03) atIndex:10];
                [encoder setBytes:&ne10 length:sizeof(ne10) atIndex:11];
                [encoder setBytes:&ne11 length:sizeof(ne11) atIndex:12];
                [encoder setBytes:&ne12 length:sizeof(ne12) atIndex:13];
                [encoder setBytes:&ne13 length:sizeof(ne13) atIndex:14];
                [encoder setBytes:&nb10 length:sizeof(nb10) atIndex:15];
                [encoder setBytes:&nb11 length:sizeof(nb11) atIndex:16];
                [encoder setBytes:&nb12 length:sizeof(nb12) atIndex:17];
                [encoder setBytes:&nb13 length:sizeof(nb13) atIndex:18];
                [encoder setBytes:&ne0  length:sizeof(ne0)  atIndex:19];
                [encoder setBytes:&ne1  length:sizeof(ne1)  atIndex:20];
                [encoder setBytes:&ne2  length:sizeof(ne2)  atIndex:21];
                [encoder setBytes:&ne3  length:sizeof(ne3)  atIndex:22];
                [encoder setBytes:&nb0  length:sizeof(nb0)  atIndex:23];
                [encoder setBytes:&nb1  length:sizeof(nb1)  atIndex:24];
                [encoder setBytes:&nb2  length:sizeof(nb2)  atIndex:25];
                [encoder setBytes:&nb3  length:sizeof(nb3)  atIndex:26];
                [encoder setBytes:&offs length:sizeof(offs) atIndex:27];
                [encoder setBytes:&nb   length:sizeof(nb)   atIndex:28];

                if (bcast_row) {
                    const int64_t n = ggml_nelements(dst)/4;

                    [encoder dispatchThreadgroups:MTLSizeMake(n, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
                } else {
                    const int nth = MIN((int) pipeline.maxTotalThreadsPerThreadgroup, ne0);

                    [encoder dispatchThreadgroups:MTLSizeMake(ne01, ne02, ne03) threadsPerThreadgroup:MTLSizeMake(nth, 1, 1)];
                }
            } break;
        case GGML_OP_MULTI_ADD:
            {
                GGML_ASSERT(src0t == GGML_TYPE_F32);
                GGML_ASSERT(dstt  == GGML_TYPE_F32);
                GGML_ASSERT(ne02 == 1 && ne03 == 1);
                GGML_ASSERT(nb0 == sizeof(float) && nb00 == sizeof(float));
                GGML_ASSERT(ggml_are_same_shape(src0, dst));

                int n_expert = dst->op_params[0];
                GGML_ASSERT(n_expert >= 2);

                id<MTLComputePipelineState> pipeline = nil;
                int64_t n = ne0*ne1;
                if (ne0%4 == 0) {
                    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MULTI_ADD_4].pipeline;
                    n /= 4;
                } else {
                    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MULTI_ADD].pipeline;
                }
                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0 offset:offs_src0 atIndex:0];
                [encoder setBuffer:id_dst  offset:offs_dst  atIndex:1];
                [encoder setBytes:&ne0  length:sizeof(ne0)  atIndex:2];
                [encoder setBytes:&ne1  length:sizeof(ne1)  atIndex:3];
                [encoder setBytes:&nb1  length:sizeof(nb1)  atIndex:4];
                [encoder setBytes:&nb01 length:sizeof(nb01) atIndex:5];
                [encoder setBytes:&n_expert length:sizeof(n_expert) atIndex:6];

                [encoder dispatchThreadgroups:MTLSizeMake(n, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
            } break;
        case GGML_OP_REPEAT:
            {
                id<MTLComputePipelineState> pipeline;

                switch (src0t) {
                    case GGML_TYPE_F32: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_REPEAT_F32].pipeline; break;
                    case GGML_TYPE_F16: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_REPEAT_F16].pipeline; break;
                    case GGML_TYPE_I32: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_REPEAT_I32].pipeline; break;
                    case GGML_TYPE_I16: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_REPEAT_I16].pipeline; break;
                    default: GGML_ABORT("fatal error");
                }

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0 offset:offs_src0 atIndex:0];
                [encoder setBuffer:id_dst  offset:offs_dst  atIndex:1];
                [encoder setBytes:&ne00 length:sizeof(ne00) atIndex:2];
                [encoder setBytes:&ne01 length:sizeof(ne01) atIndex:3];
                [encoder setBytes:&ne02 length:sizeof(ne02) atIndex:4];
                [encoder setBytes:&ne03 length:sizeof(ne03) atIndex:5];
                [encoder setBytes:&nb00 length:sizeof(nb00) atIndex:6];
                [encoder setBytes:&nb01 length:sizeof(nb01) atIndex:7];
                [encoder setBytes:&nb02 length:sizeof(nb02) atIndex:8];
                [encoder setBytes:&nb03 length:sizeof(nb03) atIndex:9];
                [encoder setBytes:&ne0  length:sizeof(ne0)  atIndex:10];
                [encoder setBytes:&ne1  length:sizeof(ne1)  atIndex:11];
                [encoder setBytes:&ne2  length:sizeof(ne2)  atIndex:12];
                [encoder setBytes:&ne3  length:sizeof(ne3)  atIndex:13];
                [encoder setBytes:&nb0  length:sizeof(nb0)  atIndex:14];
                [encoder setBytes:&nb1  length:sizeof(nb1)  atIndex:15];
                [encoder setBytes:&nb2  length:sizeof(nb2)  atIndex:16];
                [encoder setBytes:&nb3  length:sizeof(nb3)  atIndex:17];

                const int nth = MIN((int) pipeline.maxTotalThreadsPerThreadgroup, ne0);

                [encoder dispatchThreadgroups:MTLSizeMake(ne1, ne2, ne3) threadsPerThreadgroup:MTLSizeMake(nth, 1, 1)];
            } break;
        case GGML_OP_ACC:
            {
                GGML_ASSERT(src0t == GGML_TYPE_F32);
                GGML_ASSERT(src1t == GGML_TYPE_F32);
                GGML_ASSERT(dstt  == GGML_TYPE_F32);

                GGML_ASSERT(ggml_is_contiguous(src0));
                GGML_ASSERT(ggml_is_contiguous(src1));

                const size_t pnb1 = ((int32_t *) dst->op_params)[0];
                const size_t pnb2 = ((int32_t *) dst->op_params)[1];
                const size_t pnb3 = ((int32_t *) dst->op_params)[2];
                const size_t offs = ((int32_t *) dst->op_params)[3];

                const bool inplace = (bool) ((int32_t *) dst->op_params)[4];

                if (!inplace) {
                    // run a separete kernel to cpy src->dst
                    // not sure how to avoid this
                    // TODO: make a simpler cpy_bytes kernel

                    const id<MTLComputePipelineState> pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_CPY_F32_F32].pipeline;

                    [encoder setComputePipelineState:pipeline];
                    [encoder setBuffer:id_src0 offset:offs_src0        atIndex:0];
                    [encoder setBuffer:id_dst  offset:offs_dst         atIndex:1];
                    [encoder setBytes:&ne00    length:sizeof( int64_t) atIndex:2];
                    [encoder setBytes:&ne01    length:sizeof( int64_t) atIndex:3];
                    [encoder setBytes:&ne02    length:sizeof( int64_t) atIndex:4];
                    [encoder setBytes:&ne03    length:sizeof( int64_t) atIndex:5];
                    [encoder setBytes:&nb00    length:sizeof(uint64_t) atIndex:6];
                    [encoder setBytes:&nb01    length:sizeof(uint64_t) atIndex:7];
                    [encoder setBytes:&nb02    length:sizeof(uint64_t) atIndex:8];
                    [encoder setBytes:&nb03    length:sizeof(uint64_t) atIndex:9];
                    [encoder setBytes:&ne0     length:sizeof( int64_t) atIndex:10];
                    [encoder setBytes:&ne1     length:sizeof( int64_t) atIndex:11];
                    [encoder setBytes:&ne2     length:sizeof( int64_t) atIndex:12];
                    [encoder setBytes:&ne3     length:sizeof( int64_t) atIndex:13];
                    [encoder setBytes:&nb0     length:sizeof(uint64_t) atIndex:14];
                    [encoder setBytes:&nb1     length:sizeof(uint64_t) atIndex:15];
                    [encoder setBytes:&nb2     length:sizeof(uint64_t) atIndex:16];
                    [encoder setBytes:&nb3     length:sizeof(uint64_t) atIndex:17];

                    const int nth = MIN((int) pipeline.maxTotalThreadsPerThreadgroup, ne00);

                    [encoder dispatchThreadgroups:MTLSizeMake(ne01, ne02, ne03) threadsPerThreadgroup:MTLSizeMake(nth, 1, 1)];
                }

                const id<MTLComputePipelineState> pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_ADD].pipeline;

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0 offset:offs_src0 atIndex:0];
                [encoder setBuffer:id_src1 offset:offs_src1 atIndex:1];
                [encoder setBuffer:id_dst  offset:offs_dst  atIndex:2];
                [encoder setBytes:&ne00 length:sizeof(ne00) atIndex:3];
                [encoder setBytes:&ne01 length:sizeof(ne01) atIndex:4];
                [encoder setBytes:&ne02 length:sizeof(ne02) atIndex:5];
                [encoder setBytes:&ne03 length:sizeof(ne03) atIndex:6];
                [encoder setBytes:&nb00 length:sizeof(nb00) atIndex:7];
                [encoder setBytes:&pnb1 length:sizeof(pnb1) atIndex:8];
                [encoder setBytes:&pnb2 length:sizeof(pnb2) atIndex:9];
                [encoder setBytes:&pnb3 length:sizeof(pnb3) atIndex:10];
                [encoder setBytes:&ne10 length:sizeof(ne10) atIndex:11];
                [encoder setBytes:&ne11 length:sizeof(ne11) atIndex:12];
                [encoder setBytes:&ne12 length:sizeof(ne12) atIndex:13];
                [encoder setBytes:&ne13 length:sizeof(ne13) atIndex:14];
                [encoder setBytes:&nb10 length:sizeof(nb10) atIndex:15];
                [encoder setBytes:&nb11 length:sizeof(nb11) atIndex:16];
                [encoder setBytes:&nb12 length:sizeof(nb12) atIndex:17];
                [encoder setBytes:&nb13 length:sizeof(nb13) atIndex:18];
                [encoder setBytes:&ne0  length:sizeof(ne0)  atIndex:19];
                [encoder setBytes:&ne1  length:sizeof(ne1)  atIndex:20];
                [encoder setBytes:&ne2  length:sizeof(ne2)  atIndex:21];
                [encoder setBytes:&ne3  length:sizeof(ne3)  atIndex:22];
                [encoder setBytes:&nb0  length:sizeof(nb0)  atIndex:23];
                [encoder setBytes:&pnb1 length:sizeof(pnb1) atIndex:24];
                [encoder setBytes:&pnb2 length:sizeof(pnb2) atIndex:25];
                [encoder setBytes:&pnb3 length:sizeof(pnb3) atIndex:26];
                [encoder setBytes:&offs length:sizeof(offs) atIndex:27];

                const int nth = MIN((int) pipeline.maxTotalThreadsPerThreadgroup, ne00);

                [encoder dispatchThreadgroups:MTLSizeMake(ne11, ne12, ne13) threadsPerThreadgroup:MTLSizeMake(nth, 1, 1)];
            } break;
        case GGML_OP_SCALE:
            {
                GGML_ASSERT(ggml_is_contiguous(src0));

                float scale;
                memcpy(&scale, dst->op_params, sizeof(scale));

                int64_t n = ggml_nelements(dst);

                id<MTLComputePipelineState> pipeline = nil;

                if (n % 4 == 0) {
                    n /= 4;
                    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_SCALE_4].pipeline;
                } else {
                    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_SCALE].pipeline;
                }

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0   offset:offs_src0 atIndex:0];
                [encoder setBuffer:id_dst    offset:offs_dst  atIndex:1];
                [encoder setBytes:&scale length:sizeof(scale) atIndex:2];

                [encoder dispatchThreadgroups:MTLSizeMake(n, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
            } break;
        case GGML_OP_SOFTCAP:
            {
                GGML_ASSERT(ggml_is_contiguous(src0));

                float scales[2];
                memcpy(scales, dst->op_params, sizeof(scales));

                int64_t n = ggml_nelements(dst);

                id<MTLComputePipelineState> pipeline = nil;

                if (n % 4 == 0) {
                    n /= 4;
                    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_SOFTCAP_4].pipeline;
                } else {
                    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_SOFTCAP].pipeline;
                }

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0   offset:offs_src0 atIndex:0];
                [encoder setBuffer:id_dst    offset:offs_dst  atIndex:1];
                [encoder setBytes:&scales[0] length:sizeof(float) atIndex:2];
                [encoder setBytes:&scales[1] length:sizeof(float) atIndex:3];

                [encoder dispatchThreadgroups:MTLSizeMake(n, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
            } break;
        case GGML_OP_CLAMP:
            {
                id<MTLComputePipelineState> pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_CLAMP].pipeline;

                float min;
                float max;
                memcpy(&min, ((int32_t *) dst->op_params) + 0, sizeof(float));
                memcpy(&max, ((int32_t *) dst->op_params) + 1, sizeof(float));

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0   offset:offs_src0 atIndex:0];
                [encoder setBuffer:id_dst    offset:offs_dst  atIndex:1];
                [encoder setBytes:&min length:sizeof(min) atIndex:2];
                [encoder setBytes:&max length:sizeof(max) atIndex:3];

                const int64_t n = ggml_nelements(dst);

                [encoder dispatchThreadgroups:MTLSizeMake(n, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
            } break;
        case GGML_OP_UNARY:
            switch (ggml_get_unary_op(node)) {
                // we are not taking into account the strides, so for now require contiguous tensors
                GGML_ASSERT(ggml_is_contiguous(src0));

                case GGML_UNARY_OP_TANH:
                {
                    id<MTLComputePipelineState> pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_TANH].pipeline;

                    [encoder setComputePipelineState:pipeline];
                    [encoder setBuffer:id_src0 offset:offs_src0 atIndex:0];
                    [encoder setBuffer:id_dst  offset:offs_dst  atIndex:1];

                    const int64_t n = ggml_nelements(dst);

                    [encoder dispatchThreadgroups:MTLSizeMake(n, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
                } break;
                case GGML_UNARY_OP_RELU:
                {
                    id<MTLComputePipelineState> pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_RELU].pipeline;

                    [encoder setComputePipelineState:pipeline];
                    [encoder setBuffer:id_src0 offset:offs_src0 atIndex:0];
                    [encoder setBuffer:id_dst  offset:offs_dst  atIndex:1];

                    const int64_t n = ggml_nelements(dst);

                    [encoder dispatchThreadgroups:MTLSizeMake(n, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
                } break;
                case GGML_UNARY_OP_SIGMOID:
                {
                    id<MTLComputePipelineState> pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_SIGMOID].pipeline;

                    [encoder setComputePipelineState:pipeline];
                    [encoder setBuffer:id_src0 offset:offs_src0 atIndex:0];
                    [encoder setBuffer:id_dst  offset:offs_dst  atIndex:1];

                    const int64_t n = ggml_nelements(dst);

                    [encoder dispatchThreadgroups:MTLSizeMake(n, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
                } break;
                case GGML_UNARY_OP_GELU:
                {
                    int64_t n = ggml_nelements(dst);

                    id<MTLComputePipelineState> pipeline = nil;

                    if (n % 4 == 0) {
                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GELU_4].pipeline;
                        n /= 4;
                    } else {
                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GELU].pipeline;
                    }

                    [encoder setComputePipelineState:pipeline];
                    [encoder setBuffer:id_src0 offset:offs_src0 atIndex:0];
                    [encoder setBuffer:id_dst  offset:offs_dst  atIndex:1];

                    [encoder dispatchThreadgroups:MTLSizeMake(n, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
                } break;
                case GGML_UNARY_OP_GELU_QUICK:
                {
                    int64_t n = ggml_nelements(dst);

                    id<MTLComputePipelineState> pipeline = nil;

                    if (n % 4 == 0) {
                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GELU_QUICK_4].pipeline;
                        n /= 4;
                    } else {
                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GELU_QUICK].pipeline;
                    }

                    [encoder setComputePipelineState:pipeline];
                    [encoder setBuffer:id_src0 offset:offs_src0 atIndex:0];
                    [encoder setBuffer:id_dst  offset:offs_dst  atIndex:1];

                    [encoder dispatchThreadgroups:MTLSizeMake(n, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
                } break;
                case GGML_UNARY_OP_SILU:
                {
                    int64_t n = ggml_nelements(dst);

                    id<MTLComputePipelineState> pipeline = nil;

                    if (n % 4 == 0) {
                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_SILU_4].pipeline;
                        n /= 4;
                    } else {
                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_SILU].pipeline;
                    }

                    [encoder setComputePipelineState:pipeline];
                    [encoder setBuffer:id_src0 offset:offs_src0 atIndex:0];
                    [encoder setBuffer:id_dst  offset:offs_dst  atIndex:1];

                    [encoder dispatchThreadgroups:MTLSizeMake(n, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
                } break;
                case GGML_UNARY_OP_SWIGLU:
                {
                    int64_t n = ggml_nelements(dst);
                    GGML_ASSERT(ne0 == src0->ne[0]/2);

                    id<MTLComputePipelineState> pipeline = nil;

                    uint32_t n_per_row = ne0;
                    uint32_t stride    = src0->nb[1]/sizeof(float);

                    if (ne0 % 4 == 0) {
                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_SWIGLU_4].pipeline;
                        n /= 4;
                        n_per_row /= 4;
                        stride /= 4;
                    } else {
                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_SWIGLU].pipeline;
                    }

                    [encoder setComputePipelineState:pipeline];
                    [encoder setBuffer:id_src0 offset:offs_src0 atIndex:0];
                    [encoder setBuffer:id_dst  offset:offs_dst  atIndex:1];
                    [encoder setBytes:&n_per_row length:sizeof(n_per_row) atIndex:2];
                    [encoder setBytes:&stride length:sizeof(stride) atIndex:3];

                    [encoder dispatchThreadgroups:MTLSizeMake(n, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
                } break;
                default:
                {
                    GGML_METAL_LOG_WARN("%s: node %s, op = %8s not implemented\n", __func__, dst->name, ggml_op_name(dst->op));
                    GGML_ABORT("fatal error");
                }
            } break;
        case GGML_OP_FUSED_MUL_UNARY:
            {
                int64_t n = ggml_nelements(dst);
                enum ggml_unary_op op = (enum ggml_unary_op)dst->op_params[0];
                id<MTLComputePipelineState> pipeline = nil;
                if (n % 4 == 0 && op != GGML_UNARY_OP_RELU) {
                    pipeline = op == GGML_UNARY_OP_GELU ? ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_GELU_4].pipeline
                        : ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_SILU_4].pipeline;
                    n /= 4;
                } else {
                    pipeline = op == GGML_UNARY_OP_GELU ? ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_GELU].pipeline
                        : op == GGML_UNARY_OP_SILU ? ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_SILU].pipeline
                        : ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_RELU].pipeline;
                }
                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0 offset:offs_src0 atIndex:0];
                [encoder setBuffer:id_src1 offset:offs_src1 atIndex:1];
                [encoder setBuffer:id_dst  offset:offs_dst  atIndex:2];
                [encoder dispatchThreadgroups:MTLSizeMake(n, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
            } break;
        case GGML_OP_SQR:
            {
                GGML_ASSERT(ggml_is_contiguous(src0));

                id<MTLComputePipelineState> pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_SQR].pipeline;

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0 offset:offs_src0 atIndex:0];
                [encoder setBuffer:id_dst  offset:offs_dst atIndex:1];

                const int64_t n = ggml_nelements(dst);

                [encoder dispatchThreadgroups:MTLSizeMake(n, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
            } break;
        case GGML_OP_SUM_ROWS:
            {
                GGML_ASSERT(src0->nb[0] == ggml_type_size(src0->type));

                id<MTLComputePipelineState> pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_SUM_ROWS].pipeline;

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0 offset:offs_src0 atIndex:0];
                [encoder setBuffer:id_dst  offset:offs_dst  atIndex:1];
                [encoder setBytes:&ne00 length:sizeof(ne00) atIndex:2];
                [encoder setBytes:&ne01 length:sizeof(ne01) atIndex:3];
                [encoder setBytes:&ne02 length:sizeof(ne02) atIndex:4];
                [encoder setBytes:&ne03 length:sizeof(ne03) atIndex:5];
                [encoder setBytes:&nb00 length:sizeof(nb00) atIndex:6];
                [encoder setBytes:&nb01 length:sizeof(nb01) atIndex:7];
                [encoder setBytes:&nb02 length:sizeof(nb02) atIndex:8];
                [encoder setBytes:&nb03 length:sizeof(nb03) atIndex:9];
                [encoder setBytes:&ne10 length:sizeof(ne10) atIndex:10];
                [encoder setBytes:&ne11 length:sizeof(ne11) atIndex:11];
                [encoder setBytes:&ne12 length:sizeof(ne12) atIndex:12];
                [encoder setBytes:&ne13 length:sizeof(ne13) atIndex:13];
                [encoder setBytes:&nb10 length:sizeof(nb10) atIndex:14];
                [encoder setBytes:&nb11 length:sizeof(nb11) atIndex:15];
                [encoder setBytes:&nb12 length:sizeof(nb12) atIndex:16];
                [encoder setBytes:&nb13 length:sizeof(nb13) atIndex:17];
                [encoder setBytes:&ne0  length:sizeof(ne0)  atIndex:18];
                [encoder setBytes:&ne1  length:sizeof(ne1)  atIndex:19];
                [encoder setBytes:&ne2  length:sizeof(ne2)  atIndex:20];
                [encoder setBytes:&ne3  length:sizeof(ne3)  atIndex:21];
                [encoder setBytes:&nb0  length:sizeof(nb0)  atIndex:22];
                [encoder setBytes:&nb1  length:sizeof(nb1)  atIndex:23];
                [encoder setBytes:&nb2  length:sizeof(nb2)  atIndex:24];
                [encoder setBytes:&nb3  length:sizeof(nb3)  atIndex:25];

                [encoder dispatchThreadgroups:MTLSizeMake(ne01, ne02, ne03) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
            } break;
        case GGML_OP_SOFT_MAX:
            {
                GGML_ASSERT(!src1 || src1->type == GGML_TYPE_F16 || src1->type == GGML_TYPE_F32);

                int nth = 32; // SIMD width

                id<MTLComputePipelineState> pipeline = nil;

                const bool use_f16 = (src1 && src1->type == GGML_TYPE_F16);

                if (ne00%4 == 0) {
                    while (nth < ne00/4 && nth*ne01*ne02*ne03 < 256) {
                        nth *= 2;
                    }
                    if (use_f16) {
                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_SOFT_MAX_F16_4].pipeline;
                    } else {
                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_SOFT_MAX_F32_4].pipeline;
                    }
                } else {
                    while (nth < ne00 && nth*ne01*ne02*ne03 < 256) {
                        nth *= 2;
                    }
                    if (use_f16) {
                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_SOFT_MAX_F16].pipeline;
                    } else {
                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_SOFT_MAX_F32].pipeline;
                    }
                }

                float scale;
                float max_bias;

                memcpy(&scale,    ((int32_t *) dst->op_params) + 0, sizeof(scale));
                memcpy(&max_bias, ((int32_t *) dst->op_params) + 1, sizeof(max_bias));

                const int64_t nrows_x = ggml_nrows(src0);
                const int64_t nrows_y = src0->ne[1];

                const uint32_t n_head      = nrows_x/nrows_y;
                const uint32_t n_head_log2 = 1u << (uint32_t) floorf(log2f((float) n_head));

                const float m0 = powf(2.0f, -(max_bias       ) / n_head_log2);
                const float m1 = powf(2.0f, -(max_bias / 2.0f) / n_head_log2);

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0 offset:offs_src0   atIndex:0];
                if (id_src1) {
                    [encoder setBuffer:id_src1 offset:offs_src1   atIndex:1];
                } else {
                    [encoder setBuffer:id_src0 offset:offs_src0   atIndex:1];
                }
                [encoder setBuffer:id_dst      offset:offs_dst            atIndex:2];
                [encoder setBytes:&ne00        length:sizeof(ne00)        atIndex:3];
                [encoder setBytes:&ne01        length:sizeof(ne01)        atIndex:4];
                [encoder setBytes:&ne02        length:sizeof(ne02)        atIndex:5];
                [encoder setBytes:&scale       length:sizeof(scale)       atIndex:6];
                [encoder setBytes:&max_bias    length:sizeof(max_bias)    atIndex:7];
                [encoder setBytes:&m0          length:sizeof(m0)          atIndex:8];
                [encoder setBytes:&m1          length:sizeof(m1)          atIndex:9];
                [encoder setBytes:&n_head_log2 length:sizeof(n_head_log2) atIndex:10];
                [encoder setThreadgroupMemoryLength:32*sizeof(float) atIndex:0];

                [encoder dispatchThreadgroups:MTLSizeMake(ne01*ne02*ne03, 1, 1) threadsPerThreadgroup:MTLSizeMake(nth, 1, 1)];
            } break;
        case GGML_OP_SOFT_CAP_MAX:
            {
                GGML_ASSERT(!src1 || src1->type == GGML_TYPE_F16 || src1->type == GGML_TYPE_F32);

                int nth = 32; // SIMD width

                id<MTLComputePipelineState> pipeline = nil;

                const bool use_f16 = (src1 && src1->type == GGML_TYPE_F16);

                if (ne00%4 == 0) {
                    while (nth < ne00/4 && nth*ne01*ne02*ne03 < 256) {
                        nth *= 2;
                    }
                    if (use_f16) {
                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_SOFT_CAP_MAX_F16_4].pipeline;
                    } else {
                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_SOFT_CAP_MAX_F32_4].pipeline;
                    }
                } else {
                    while (nth < ne00 && nth*ne01*ne02*ne03 < 256) {
                        nth *= 2;
                    }
                    if (use_f16) {
                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_SOFT_CAP_MAX_F16].pipeline;
                    } else {
                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_SOFT_CAP_MAX_F32].pipeline;
                    }
                }

                float scale;
                float max_bias;
                float s_before;
                float s_after;

                memcpy(&scale,    ((int32_t *) dst->op_params) + 0, sizeof(scale));
                memcpy(&max_bias, ((int32_t *) dst->op_params) + 1, sizeof(max_bias));
                memcpy(&s_before, ((int32_t *) dst->op_params) + 2, sizeof(s_before));
                memcpy(&s_after,  ((int32_t *) dst->op_params) + 3, sizeof(s_after));

                const int64_t nrows_x = ggml_nrows(src0);
                const int64_t nrows_y = src0->ne[1];

                const uint32_t n_head      = nrows_x/nrows_y;
                const uint32_t n_head_log2 = 1u << (uint32_t) floorf(log2f((float) n_head));

                const float m0 = powf(2.0f, -(max_bias       ) / n_head_log2);
                const float m1 = powf(2.0f, -(max_bias / 2.0f) / n_head_log2);

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0 offset:offs_src0   atIndex:0];
                if (id_src1) {
                    [encoder setBuffer:id_src1 offset:offs_src1   atIndex:1];
                } else {
                    [encoder setBuffer:id_src0 offset:offs_src0   atIndex:1];
                }
                [encoder setBuffer:id_dst      offset:offs_dst            atIndex:2];
                [encoder setBytes:&ne00        length:sizeof(ne00)        atIndex:3];
                [encoder setBytes:&ne01        length:sizeof(ne01)        atIndex:4];
                [encoder setBytes:&ne02        length:sizeof(ne02)        atIndex:5];
                [encoder setBytes:&scale       length:sizeof(scale)       atIndex:6];
                [encoder setBytes:&max_bias    length:sizeof(max_bias)    atIndex:7];
                [encoder setBytes:&m0          length:sizeof(m0)          atIndex:8];
                [encoder setBytes:&m1          length:sizeof(m1)          atIndex:9];
                [encoder setBytes:&s_before    length:sizeof(s_before)    atIndex:10];
                [encoder setBytes:&s_after     length:sizeof(s_after )    atIndex:11];
                [encoder setBytes:&n_head_log2 length:sizeof(n_head_log2) atIndex:12];
                [encoder setThreadgroupMemoryLength:32*sizeof(float) atIndex:0];

                [encoder dispatchThreadgroups:MTLSizeMake(ne01*ne02*ne03, 1, 1) threadsPerThreadgroup:MTLSizeMake(nth, 1, 1)];
            } break;
        case GGML_OP_DIAG_MASK_INF:
            {
                const int n_past = ((int32_t *)(dst->op_params))[0];

                id<MTLComputePipelineState> pipeline = nil;

                if (ne00%8 == 0) {
                    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_DIAG_MASK_INF_8].pipeline;
                } else {
                    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_DIAG_MASK_INF].pipeline;
                }

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0 offset:offs_src0 atIndex:0];
                [encoder setBuffer:id_dst  offset:offs_dst  atIndex:1];
                [encoder setBytes:&ne00   length:sizeof(ne00) atIndex:2];
                [encoder setBytes:&ne01   length:sizeof(ne01) atIndex:3];
                [encoder setBytes:&n_past length:sizeof(int)  atIndex:4];

                if (ne00%8 == 0) {
                    [encoder dispatchThreadgroups:MTLSizeMake(ne00*ne01*ne02/8, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
                }
                else {
                    [encoder dispatchThreadgroups:MTLSizeMake(ne00, ne01, ne02) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
                }
            } break;
        case GGML_OP_MUL_MAT:
            {
                GGML_ASSERT(ne00 == ne10);

                GGML_ASSERT(ne12 % ne02 == 0);
                GGML_ASSERT(ne13 % ne03 == 0);

                const uint r2 = ne12/ne02;
                const uint r3 = ne13/ne03;

                // find the break-even point where the matrix-matrix kernel becomes more efficient compared
                // to the matrix-vector kernel
                int ne11_mm_min = 4;

#if 0
                // the numbers below are measured on M2 Ultra for 7B and 13B models
                // these numbers do not translate to other devices or model sizes
                // TODO: need to find a better approach
                        if ([ctx->device.name isEqualToString:@"Apple M2 Ultra"]) {
                            switch (src0t) {
                                case GGML_TYPE_F16:  ne11_mm_min = 2;  break;
                                case GGML_TYPE_Q8_0: ne11_mm_min = 7;  break;
                                case GGML_TYPE_Q2_K: ne11_mm_min = 15; break;
                                case GGML_TYPE_Q3_K: ne11_mm_min = 7;  break;
                                case GGML_TYPE_Q4_0:
                                case GGML_TYPE_Q4_1: ne11_mm_min = 15; break;
                                case GGML_TYPE_Q4_K: ne11_mm_min = 11; break;
                                case GGML_TYPE_Q5_0:                          // not tested yet
                                case GGML_TYPE_Q5_1: ne11_mm_min = 13; break; // not tested yet
                                case GGML_TYPE_Q5_K: ne11_mm_min = 7;  break;
                                case GGML_TYPE_Q6_K: ne11_mm_min = 7;  break;
                                default:             ne11_mm_min = 1;  break;
                            }
                        }
#endif

                        // for now the matrix-matrix multiplication kernel only works on A14+/M1+ SoCs
                        // AMD GPU and older A-chips will reuse matrix-vector multiplication kernel
                        if ([ctx->device supportsFamily:MTLGPUFamilyApple7] &&
                                !ggml_is_transposed(src0) &&
                                !ggml_is_transposed(src1) &&
                                (src1t == GGML_TYPE_F32 || src1t == GGML_TYPE_F16) &&
                                ne00 % 32 == 0 && ne00 >= 64 &&
                                (ne11 > ne11_mm_min || (ggml_is_quantized(src0t) && ne12 > 1))) {
                            //printf("matrix: ne00 = %6d, ne01 = %6d, ne02 = %6d, ne11 = %6d, ne12 = %6d\n", ne00, ne01, ne02, ne11, ne12);

                            // some Metal matrix data types require aligned pointers
                            // ref: https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf (Table 2.5)
                            switch (src0->type) {
                                case GGML_TYPE_F32:  GGML_ASSERT(nb01 % 16 == 0); break;
                                case GGML_TYPE_F16:  GGML_ASSERT(nb01 % 8  == 0); break;
                                default: break;
                            }

                            id<MTLComputePipelineState> pipeline = nil;

                            if (src1->type == GGML_TYPE_F32) {
                                switch (src0->type) {
                                    case GGML_TYPE_F32:     pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_F32_F32    ].pipeline; break;
                                    case GGML_TYPE_F16:     pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_F16_F32    ].pipeline; break;
                                    case GGML_TYPE_BF16:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_BF16_F32   ].pipeline; break;
                                    case GGML_TYPE_Q4_0:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_Q4_0_F32   ].pipeline; break;
                                    case GGML_TYPE_Q4_1:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_Q4_1_F32   ].pipeline; break;
                                    case GGML_TYPE_Q5_0:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_Q5_0_F32   ].pipeline; break;
                                    case GGML_TYPE_Q6_0:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_Q6_0_F32   ].pipeline; break;
                                    case GGML_TYPE_Q5_1:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_Q5_1_F32   ].pipeline; break;
                                    case GGML_TYPE_Q8_0:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_Q8_0_F32   ].pipeline; break;
                                    case GGML_TYPE_Q2_K:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_Q2_K_F32   ].pipeline; break;
                                    case GGML_TYPE_Q3_K:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_Q3_K_F32   ].pipeline; break;
                                    case GGML_TYPE_Q4_K:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_Q4_K_F32   ].pipeline; break;
                                    case GGML_TYPE_Q5_K:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_Q5_K_F32   ].pipeline; break;
                                    case GGML_TYPE_Q6_K:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_Q6_K_F32   ].pipeline; break;
                                    case GGML_TYPE_IQ2_XXS: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_XXS_F32].pipeline; break;
                                    case GGML_TYPE_IQ2_XS:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_XS_F32 ].pipeline; break;
                                    case GGML_TYPE_IQ3_XXS: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_XXS_F32].pipeline; break;
                                    case GGML_TYPE_IQ3_S:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_S_F32  ].pipeline; break;
                                    case GGML_TYPE_IQ2_S:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_S_F32  ].pipeline; break;
                                    case GGML_TYPE_IQ1_S:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ1_S_F32  ].pipeline; break;
                                    case GGML_TYPE_IQ1_M:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ1_M_F32  ].pipeline; break;
                                    case GGML_TYPE_IQ1_BN:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ1_BN_F32 ].pipeline; break;
                                    case GGML_TYPE_IQ2_BN:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_BN_F32 ].pipeline; break;
                                    case GGML_TYPE_IQ4_NL:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_NL_F32 ].pipeline; break;
                                    case GGML_TYPE_IQ4_XS:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_XS_F32 ].pipeline; break;
                                    case GGML_TYPE_IQ3_KS:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_KS_F32 ].pipeline; break;
                                    case GGML_TYPE_IQ4_KS:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_KS_F32 ].pipeline; break;
                                    case GGML_TYPE_IQ4_KSS: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_KSS_F32].pipeline; break;
                                    case GGML_TYPE_IQ5_KS:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ5_KS_F32 ].pipeline; break;
                                    case GGML_TYPE_IQ2_K:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_K_F32  ].pipeline; break;
                                    case GGML_TYPE_IQ2_KS:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_KS_F32 ].pipeline; break;
                                    case GGML_TYPE_IQ2_KL:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_KL_F32 ].pipeline; break;
                                    case GGML_TYPE_IQ3_K:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_K_F32  ].pipeline; break;
                                    case GGML_TYPE_IQ4_K:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_K_F32  ].pipeline; break;
                                    case GGML_TYPE_IQ5_K:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ5_K_F32  ].pipeline; break;
                                    case GGML_TYPE_IQ6_K:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ6_K_F32  ].pipeline; break;
                                    case GGML_TYPE_IQ2_KT:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_KT_F32 ].pipeline; break;
                                    case GGML_TYPE_IQ3_KT:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_KT_F32 ].pipeline; break;
                                    //case GGML_TYPE_IQ4_KT:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_KT_F32 ].pipeline; break;
                                    default: GGML_ABORT("MUL MAT-MAT not implemented");
                                }
                            }
                            else if (src1->type == GGML_TYPE_F16) {
                                switch (src0->type) {
                                    case GGML_TYPE_F32:     pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_F32_F16    ].pipeline; break;
                                    case GGML_TYPE_F16:     pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_F16_F16    ].pipeline; break;
                                    case GGML_TYPE_BF16:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_BF16_F16   ].pipeline; break;
                                    case GGML_TYPE_Q4_0:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_Q4_0_F16   ].pipeline; break;
                                    case GGML_TYPE_Q4_1:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_Q4_1_F16   ].pipeline; break;
                                    case GGML_TYPE_Q5_0:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_Q5_0_F16   ].pipeline; break;
                                    case GGML_TYPE_Q6_0:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_Q6_0_F16   ].pipeline; break;
                                    case GGML_TYPE_Q5_1:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_Q5_1_F16   ].pipeline; break;
                                    case GGML_TYPE_Q8_0:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_Q8_0_F16   ].pipeline; break;
                                    case GGML_TYPE_Q2_K:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_Q2_K_F16   ].pipeline; break;
                                    case GGML_TYPE_Q3_K:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_Q3_K_F16   ].pipeline; break;
                                    case GGML_TYPE_Q4_K:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_Q4_K_F16   ].pipeline; break;
                                    case GGML_TYPE_Q5_K:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_Q5_K_F16   ].pipeline; break;
                                    case GGML_TYPE_Q6_K:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_Q6_K_F16   ].pipeline; break;
                                    case GGML_TYPE_IQ2_XXS: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_XXS_F16].pipeline; break;
                                    case GGML_TYPE_IQ2_XS:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_XS_F16 ].pipeline; break;
                                    case GGML_TYPE_IQ3_XXS: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_XXS_F16].pipeline; break;
                                    case GGML_TYPE_IQ3_S:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_S_F16  ].pipeline; break;
                                    case GGML_TYPE_IQ2_S:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_S_F16  ].pipeline; break;
                                    case GGML_TYPE_IQ1_S:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ1_S_F16  ].pipeline; break;
                                    case GGML_TYPE_IQ1_M:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ1_M_F16  ].pipeline; break;
                                    case GGML_TYPE_IQ1_BN:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ1_BN_F16 ].pipeline; break;
                                    case GGML_TYPE_IQ2_BN:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_BN_F16 ].pipeline; break;
                                    case GGML_TYPE_IQ4_NL:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_NL_F16 ].pipeline; break;
                                    case GGML_TYPE_IQ4_XS:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_XS_F16 ].pipeline; break;
                                    case GGML_TYPE_IQ3_KS:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_KS_F16 ].pipeline; break;
                                    case GGML_TYPE_IQ4_KS:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_KS_F16 ].pipeline; break;
                                    case GGML_TYPE_IQ4_KSS: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_KSS_F16].pipeline; break;
                                    case GGML_TYPE_IQ5_KS:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ5_KS_F16 ].pipeline; break;
                                    case GGML_TYPE_IQ2_K:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_K_F16  ].pipeline; break;
                                    case GGML_TYPE_IQ2_KS:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_KS_F16 ].pipeline; break;
                                    case GGML_TYPE_IQ2_KL:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_KL_F16 ].pipeline; break;
                                    case GGML_TYPE_IQ3_K:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_K_F16  ].pipeline; break;
                                    case GGML_TYPE_IQ4_K:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_K_F16  ].pipeline; break;
                                    case GGML_TYPE_IQ5_K:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ5_K_F16  ].pipeline; break;
                                    case GGML_TYPE_IQ6_K:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ6_K_F16  ].pipeline; break;
                                    case GGML_TYPE_IQ2_KT:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ2_KT_F16 ].pipeline; break;
                                    case GGML_TYPE_IQ3_KT:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ3_KT_F16 ].pipeline; break;
                                    //case GGML_TYPE_IQ4_KT:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_IQ4_KT_F16 ].pipeline; break;
                                    default: GGML_ABORT("MUL MAT-MAT not implemented");
                                }
                            }
                            else {
                                GGML_ABORT("Unsupported src1 type for MUL-MAT");
                            }

                            [encoder setComputePipelineState:pipeline];
                            [encoder setBuffer:id_src0 offset:offs_src0    atIndex:0];
                            [encoder setBuffer:id_src1 offset:offs_src1    atIndex:1];
                            [encoder setBuffer:id_dst  offset:offs_dst     atIndex:2];
                            [encoder setBytes:&ne00    length:sizeof(ne00) atIndex:3];
                            [encoder setBytes:&ne02    length:sizeof(ne02) atIndex:4];
                            [encoder setBytes:&nb01    length:sizeof(nb01) atIndex:5];
                            [encoder setBytes:&nb02    length:sizeof(nb02) atIndex:6];
                            [encoder setBytes:&ne12    length:sizeof(ne12) atIndex:7];
                            [encoder setBytes:&nb10    length:sizeof(nb10) atIndex:8];
                            [encoder setBytes:&nb11    length:sizeof(nb11) atIndex:9];
                            [encoder setBytes:&nb12    length:sizeof(nb12) atIndex:10];
                            [encoder setBytes:&ne0     length:sizeof(ne0)  atIndex:11];
                            [encoder setBytes:&ne1     length:sizeof(ne1)  atIndex:12];
                            [encoder setBytes:&r2      length:sizeof(r2)   atIndex:13];
                            [encoder setBytes:&r3      length:sizeof(r3)   atIndex:14];
                            [encoder setThreadgroupMemoryLength:8192 atIndex:0];
                            [encoder dispatchThreadgroups:MTLSizeMake( (ne11 + 31)/32, (ne01 + 63)/64, ne12*ne13) threadsPerThreadgroup:MTLSizeMake(128, 1, 1)];
                        } else {
                            int nth0 = 32;
                            int nth1 = 1;
                            int nrows = 1;
                            //printf("vector: ne00 = %6d, ne01 = %6d, ne02 = %6d, ne11 = %6d, ne12 = %6d\n", ne00, ne01, ne02, ne11, ne12);

                            id<MTLComputePipelineState> pipeline = nil;

                            // use custom matrix x vector kernel
                            switch (src0t) {
                                case GGML_TYPE_F32:
                                    {
                                        GGML_ASSERT(src1t == GGML_TYPE_F32);
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_F32_F32].pipeline;
                                        nrows = 4;
                                    } break;
                                case GGML_TYPE_F16:
                                    {
                                        nth0 = 32;
                                        nth1 = 1;
                                        if (src1t == GGML_TYPE_F32) {
                                            if (ne11 * ne12 < 4) {
                                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_F16_F32_1ROW].pipeline;
                                            } else if (ne00 >= 128 && ne01 >= 8 && ne00%4 == 0) {
                                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_F16_F32_L4].pipeline;
                                                nrows = ne11;
                                            } else {
                                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_F16_F32].pipeline;
                                                nrows = 4;
                                            }
                                        } else {
                                            pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_F16_F16].pipeline;
                                            nrows = 4;
                                        }
                                    } break;
                                case GGML_TYPE_BF16:
                                    {
                                        if (src1t == GGML_TYPE_F32) {
                                            pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_BF16_F32].pipeline;
                                        }
                                        else if (src1t == GGML_TYPE_F16) {
                                            pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_BF16_F16].pipeline;
                                        }
                                        else {
                                            GGML_ABORT("not implemented");
                                        }
                                        nrows = 4;
                                    } break;
                                case GGML_TYPE_Q4_0:
                                    {
                                        nth0 = 8;
                                        nth1 = 8;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_Q4_0_F32].pipeline;
                                    } break;
                                case GGML_TYPE_Q4_1:
                                    {
                                        nth0 = 8;
                                        nth1 = 8;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_Q4_1_F32].pipeline;
                                    } break;
                                case GGML_TYPE_Q5_0:
                                    {
                                        nth0 = 8;
                                        nth1 = 8;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_Q5_0_F32].pipeline;
                                    } break;
                                case GGML_TYPE_Q5_1:
                                    {
                                        nth0 = 8;
                                        nth1 = 8;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_Q5_1_F32].pipeline;
                                    } break;
                                case GGML_TYPE_Q6_0:
                                    {
                                        nth0 = 8;
                                        nth1 = 8;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_Q6_0_F32].pipeline;
                                    } break;
                                case GGML_TYPE_Q8_0:
                                    {
                                        nth0 = 8;
                                        nth1 = 8;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_Q8_0_F32].pipeline;
                                    } break;
                                case GGML_TYPE_Q2_K:
                                    {
                                        nth0 = 2;
                                        nth1 = 32;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_Q2_K_F32].pipeline;
                                    } break;
                                case GGML_TYPE_Q3_K:
                                    {
                                        nth0 = 2;
                                        nth1 = 32;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_Q3_K_F32].pipeline;
                                    } break;
                                case GGML_TYPE_Q4_K:
                                    {
                                        nth0 = 4; //1;
                                        nth1 = 8; //32;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_Q4_K_F32].pipeline;
                                    } break;
                                case GGML_TYPE_Q5_K:
                                    {
                                        nth0 = 2;
                                        nth1 = 32;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_Q5_K_F32].pipeline;
                                    } break;
                                case GGML_TYPE_Q6_K:
                                    {
                                        nth0 = 2;
                                        nth1 = 32;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_Q6_K_F32].pipeline;
                                    } break;
                                case GGML_TYPE_IQ2_XXS:
                                    {
                                        nth0 = 4;
                                        nth1 = 16;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_IQ2_XXS_F32].pipeline;
                                    } break;
                                case GGML_TYPE_IQ2_XS:
                                    {
                                        nth0 = 4;
                                        nth1 = 16;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_IQ2_XS_F32].pipeline;
                                    } break;
                                case GGML_TYPE_IQ3_XXS:
                                    {
                                        nth0 = 4;
                                        nth1 = 16;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_IQ3_XXS_F32].pipeline;
                                    } break;
                                case GGML_TYPE_IQ3_S:
                                    {
                                        nth0 = 4;
                                        nth1 = 16;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_IQ3_S_F32].pipeline;
                                    } break;
                                case GGML_TYPE_IQ2_S:
                                    {
                                        nth0 = 4;
                                        nth1 = 16;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_IQ2_S_F32].pipeline;
                                    } break;
                                case GGML_TYPE_IQ1_S:
                                    {
                                        nth0 = 4;
                                        nth1 = 16;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_IQ1_S_F32].pipeline;
                                    } break;
                                case GGML_TYPE_IQ1_M:
                                    {
                                        nth0 = 4;
                                        nth1 = 16;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_IQ1_M_F32].pipeline;
                                    } break;
                                case GGML_TYPE_IQ1_BN:
                                    {
                                        nth0 = 4;
                                        nth1 = 16;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_IQ1_BN_F32].pipeline;
                                    } break;
                                case GGML_TYPE_IQ2_BN:
                                    {
                                        nth0 = 4;
                                        nth1 = 16;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_IQ2_BN_F32].pipeline;
                                    } break;
                                case GGML_TYPE_IQ4_NL:
                                    {
                                        nth0 = 4;
                                        nth1 = 16;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_IQ4_NL_F32].pipeline;
                                    } break;
                                case GGML_TYPE_IQ4_XS:
                                    {
                                        nth0 = 4;
                                        nth1 = 16;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_IQ4_XS_F32].pipeline;
                                    } break;
                                case GGML_TYPE_IQ3_KS:
                                    {
                                        nth0 = 4;
                                        nth1 = 16;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_IQ3_KS_F32].pipeline;
                                    } break;
                                case GGML_TYPE_IQ4_KS:
                                    {
                                        nth0 = 4;
                                        nth1 = 16;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_IQ4_KS_F32].pipeline;
                                    } break;
                                case GGML_TYPE_IQ4_KSS:
                                    {
                                        nth0 = 4;
                                        nth1 = 16;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_IQ4_KSS_F32].pipeline;
                                    } break;
                                case GGML_TYPE_IQ5_KS:
                                    {
                                        nth0 = 4;
                                        nth1 = 16;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_IQ5_KS_F32].pipeline;
                                    } break;
                                case GGML_TYPE_IQ2_K:
                                    {
                                        nth0 = 4;
                                        nth1 = 16;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_IQ2_K_F32].pipeline;
                                    } break;
                                case GGML_TYPE_IQ2_KS:
                                    {
                                        nth0 = 4;
                                        nth1 = 16;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_IQ2_KS_F32].pipeline;
                                    } break;
                                case GGML_TYPE_IQ2_KL:
                                    {
                                        nth0 = 4;
                                        nth1 = 16;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_IQ2_KL_F32].pipeline;
                                    } break;
                                case GGML_TYPE_IQ3_K:
                                    {
                                        nth0 = 4;
                                        nth1 = 16;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_IQ3_K_F32].pipeline;
                                    } break;
                                case GGML_TYPE_IQ4_K:
                                    {
                                        nth0 = 4;
                                        nth1 = 16;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_IQ4_K_F32].pipeline;
                                    } break;
                                case GGML_TYPE_IQ5_K:
                                    {
                                        nth0 = 4;
                                        nth1 = 16;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_IQ5_K_F32].pipeline;
                                    } break;
                                case GGML_TYPE_IQ6_K:
                                    {
                                        nth0 = 4;
                                        nth1 = 16;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_IQ6_K_F32].pipeline;
                                    } break;
                                case GGML_TYPE_IQ2_KT:
                                    {
                                        nth0 = 4;
                                        nth1 = 16;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_IQ2_KT_F32].pipeline;
                                    } break;
                                case GGML_TYPE_IQ3_KT:
                                    {
                                        nth0 = 4;
                                        nth1 = 16;
                                        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_IQ3_KT_F32].pipeline;
                                    } break;
                                //case GGML_TYPE_IQ4_KT:
                                //    {
                                //        nth0 = 4;
                                //        nth1 = 16;
                                //        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_IQ4_KT_F32].pipeline;
                                //    } break;
                                default:
                                    {
                                        GGML_METAL_LOG_ERROR("Asserting on type %d\n", (int)src0t);
                                        GGML_ABORT("not implemented");
                                    }
                            };

                            [encoder setComputePipelineState:pipeline];
                            [encoder setBuffer:id_src0 offset:offs_src0 atIndex:0];
                            [encoder setBuffer:id_src1 offset:offs_src1 atIndex:1];
                            [encoder setBuffer:id_dst  offset:offs_dst  atIndex:2];
                            [encoder setBytes:&ne00 length:sizeof(ne00) atIndex:3];
                            [encoder setBytes:&ne01 length:sizeof(ne01) atIndex:4];
                            [encoder setBytes:&ne02 length:sizeof(ne02) atIndex:5];
                            [encoder setBytes:&nb00 length:sizeof(nb00) atIndex:6];
                            [encoder setBytes:&nb01 length:sizeof(nb01) atIndex:7];
                            [encoder setBytes:&nb02 length:sizeof(nb02) atIndex:8];
                            [encoder setBytes:&ne10 length:sizeof(ne10) atIndex:9];
                            [encoder setBytes:&ne11 length:sizeof(ne11) atIndex:10];
                            [encoder setBytes:&ne12 length:sizeof(ne12) atIndex:11];
                            [encoder setBytes:&nb10 length:sizeof(nb10) atIndex:12];
                            [encoder setBytes:&nb11 length:sizeof(nb11) atIndex:13];
                            [encoder setBytes:&nb12 length:sizeof(nb12) atIndex:14];
                            [encoder setBytes:&ne0  length:sizeof(ne0)  atIndex:15];
                            [encoder setBytes:&ne1  length:sizeof(ne1)  atIndex:16];
                            [encoder setBytes:&r2   length:sizeof(r2)   atIndex:17];
                            [encoder setBytes:&r3   length:sizeof(r3)   atIndex:18];

                            if (src0t == GGML_TYPE_Q4_0  || src0t == GGML_TYPE_Q4_1  || src0t == GGML_TYPE_Q5_0 ||
                                    src0t == GGML_TYPE_Q5_1  || src0t == GGML_TYPE_Q8_0  || src0t == GGML_TYPE_Q2_K ||
                                    src0t == GGML_TYPE_IQ1_S || src0t == GGML_TYPE_IQ1_M || src0t == GGML_TYPE_IQ2_S||
                                    src0t == GGML_TYPE_IQ1_BN|| src0t == GGML_TYPE_IQ2_BN|| src0t == GGML_TYPE_Q6_0 ||
                                    src0t == GGML_TYPE_IQ2_KT|| src0t == GGML_TYPE_IQ3_KT) { //|| src0t == GGML_TYPE_IQ4_KT) {
                                [encoder dispatchThreadgroups:MTLSizeMake((ne01 + 7)/8, ne11, ne12*ne13) threadsPerThreadgroup:MTLSizeMake(nth0, nth1, 1)];
                            }
                            else if (src0t == GGML_TYPE_IQ2_KS || src0t == GGML_TYPE_IQ2_K || src0t == GGML_TYPE_IQ3_K || src0t == GGML_TYPE_IQ3_KS ||
                                     src0t == GGML_TYPE_IQ2_KL) {
                                const int mem_size = src0t == GGML_TYPE_IQ2_KL ? 128*sizeof(float)
                                                   : src0t == GGML_TYPE_IQ2_KS ? 64*sizeof(float)
                                                   : src0t == GGML_TYPE_IQ3_K || src0t == GGML_TYPE_IQ3_KS ? 32*sizeof(float) : 16*sizeof(float);
                                [encoder setThreadgroupMemoryLength:mem_size atIndex:0];
                                [encoder dispatchThreadgroups:MTLSizeMake((ne01 + 7)/8, ne11, ne12*ne13) threadsPerThreadgroup:MTLSizeMake(nth0, nth1, 1)];
                            }
                            else if (src0t == GGML_TYPE_IQ2_XXS || src0t == GGML_TYPE_IQ2_XS) {
                                const int mem_size = src0t == GGML_TYPE_IQ2_XXS ? 256*8+128 : 512*8+128;
                                [encoder setThreadgroupMemoryLength:mem_size atIndex:0];
                                [encoder dispatchThreadgroups:MTLSizeMake((ne01 + 7)/8, ne11, ne12*ne13) threadsPerThreadgroup:MTLSizeMake(nth0, nth1, 1)];
                            }
                            else if (src0t == GGML_TYPE_IQ3_XXS || src0t == GGML_TYPE_IQ3_S) {
                                const int mem_size = src0t == GGML_TYPE_IQ3_XXS ? 256*4+128 : 512*4;
                                [encoder setThreadgroupMemoryLength:mem_size atIndex:0];
                                [encoder dispatchThreadgroups:MTLSizeMake((ne01 + 7)/8, ne11, ne12*ne13) threadsPerThreadgroup:MTLSizeMake(nth0, nth1, 1)];
                            }
                            else if (src0t == GGML_TYPE_IQ4_NL || src0t == GGML_TYPE_IQ4_XS || src0t == GGML_TYPE_IQ4_K ||
                                    src0t == GGML_TYPE_IQ5_K  ||  src0t == GGML_TYPE_IQ6_K || src0t == GGML_TYPE_IQ4_KS||
                                    src0t == GGML_TYPE_IQ4_KSS || src0t == GGML_TYPE_IQ5_KS) {
                                const int mem_size = src0t == GGML_TYPE_IQ6_K ? 128*sizeof(float)
                                    : src0t == GGML_TYPE_IQ5_K || src0t == GGML_TYPE_IQ5_KS ? 64*sizeof(float) : 32*sizeof(float);
                                [encoder setThreadgroupMemoryLength:mem_size atIndex:0];
                                [encoder dispatchThreadgroups:MTLSizeMake((ne01 + 3)/4, ne11, ne12*ne13) threadsPerThreadgroup:MTLSizeMake(nth0, nth1, 1)];
                            }
                            else if (src0t == GGML_TYPE_Q4_K) {
                                [encoder dispatchThreadgroups:MTLSizeMake((ne01 + 3)/4, ne11, ne12*ne13) threadsPerThreadgroup:MTLSizeMake(nth0, nth1, 1)];
                            }
                            else if (src0t == GGML_TYPE_Q3_K) {
                                [encoder dispatchThreadgroups:MTLSizeMake((ne01 + 3)/4, ne11, ne12*ne13) threadsPerThreadgroup:MTLSizeMake(nth0, nth1, 1)];
                            }
                            else if (src0t == GGML_TYPE_Q5_K) {
                                [encoder dispatchThreadgroups:MTLSizeMake((ne01 + 3)/4, ne11, ne12*ne13) threadsPerThreadgroup:MTLSizeMake(nth0, nth1, 1)];
                            }
                            else if (src0t == GGML_TYPE_Q6_K) {
                                [encoder dispatchThreadgroups:MTLSizeMake((ne01 + 1)/2, ne11, ne12*ne13) threadsPerThreadgroup:MTLSizeMake(nth0, nth1, 1)];
                            } else {
                                const int64_t ny = (ne11 + nrows - 1)/nrows;
                                [encoder dispatchThreadgroups:MTLSizeMake(ne01, ny, ne12*ne13) threadsPerThreadgroup:MTLSizeMake(nth0, nth1, 1)];
                            }
                        }
            } break;
        case GGML_OP_MUL_MAT_ID:
            {
                const int n_as = src0->ne[2];

                // src2 = ids
                const enum ggml_type src2t = src2->type; GGML_UNUSED(src2t);

                GGML_ASSERT(src2t == GGML_TYPE_I32);

                GGML_ASSERT(!ggml_is_transposed(src0));
                GGML_ASSERT(!ggml_is_transposed(src1));

                GGML_ASSERT(src1t == GGML_TYPE_F32);

                // find the break-even point where the matrix-matrix kernel becomes more efficient compared
                // to the matrix-vector kernel
                // ne20 = n_used_experts
                // ne21 = n_rows
                const int dst_rows = ne20*ne21;
                const int dst_rows_min = n_as;
                //const int dst_rows_max = (ctx->device.maxThreadgroupMemoryLength/2 - 8192)/4;
                const int dst_rows_max = (ctx->device.maxThreadgroupMemoryLength - 8192)/4;

                // max size of the rowids array in the kernel shared buffer
                //GGML_ASSERT(dst_rows <= dst_rows_max);

                // for now the matrix-matrix multiplication kernel only works on A14+/M1+ SoCs
                // AMD GPU and older A-chips will reuse matrix-vector multiplication kernel
                // !!!
                // TODO: for now, always use mat-vec kernels until we figure out how to improve the
                //       indirect matrix multiplication
                // !!!
                if ([ctx->device supportsFamily:MTLGPUFamilyApple7] &&
                        ne00 % 32 == 0 && ne00 >= 64 &&
                        dst_rows > dst_rows_min &&
                        dst_rows <= dst_rows_max) {

                    // some Metal matrix data types require aligned pointers
                    // ref: https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf (Table 2.5)
                    switch (src0->type) {
                        case GGML_TYPE_F32: GGML_ASSERT(nb01 % 16 == 0); break;
                        case GGML_TYPE_F16: GGML_ASSERT(nb01 % 8  == 0); break;
                        default: break;
                    }

                    id<MTLComputePipelineState> pipeline = nil;

                    switch (src0->type) {
                        case GGML_TYPE_F32:     pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_F32_F32    ].pipeline; break;
                        case GGML_TYPE_F16:     pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_F16_F32    ].pipeline; break;
                        case GGML_TYPE_BF16:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_BF16_F32   ].pipeline; break;
                        case GGML_TYPE_Q4_0:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q4_0_F32   ].pipeline; break;
                        case GGML_TYPE_Q4_1:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q4_1_F32   ].pipeline; break;
                        case GGML_TYPE_Q5_0:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q5_0_F32   ].pipeline; break;
                        case GGML_TYPE_Q5_1:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q5_1_F32   ].pipeline; break;
                        case GGML_TYPE_Q6_0:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q6_0_F32   ].pipeline; break;
                        case GGML_TYPE_Q8_0:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q8_0_F32   ].pipeline; break;
                        case GGML_TYPE_Q2_K:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q2_K_F32   ].pipeline; break;
                        case GGML_TYPE_Q3_K:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q3_K_F32   ].pipeline; break;
                        case GGML_TYPE_Q4_K:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q4_K_F32   ].pipeline; break;
                        case GGML_TYPE_Q5_K:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q5_K_F32   ].pipeline; break;
                        case GGML_TYPE_Q6_K:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_Q6_K_F32   ].pipeline; break;
                        case GGML_TYPE_IQ2_XXS: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ2_XXS_F32].pipeline; break;
                        case GGML_TYPE_IQ2_XS:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ2_XS_F32 ].pipeline; break;
                        case GGML_TYPE_IQ3_XXS: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ3_XXS_F32].pipeline; break;
                        case GGML_TYPE_IQ3_S:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ3_S_F32  ].pipeline; break;
                        case GGML_TYPE_IQ2_S:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ2_S_F32  ].pipeline; break;
                        case GGML_TYPE_IQ1_S:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ1_S_F32  ].pipeline; break;
                        case GGML_TYPE_IQ1_M:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ1_M_F32  ].pipeline; break;
                        case GGML_TYPE_IQ1_BN:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ1_BN_F32 ].pipeline; break;
                        case GGML_TYPE_IQ2_BN:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ2_BN_F32 ].pipeline; break;
                        case GGML_TYPE_IQ4_NL:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ4_NL_F32 ].pipeline; break;
                        case GGML_TYPE_IQ4_XS:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ4_XS_F32 ].pipeline; break;
                        case GGML_TYPE_IQ3_KS:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ3_KS_F32 ].pipeline; break;
                        case GGML_TYPE_IQ4_KS:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ4_KS_F32 ].pipeline; break;
                        case GGML_TYPE_IQ4_KSS: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ4_KSS_F32].pipeline; break;
                        case GGML_TYPE_IQ5_KS:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ5_KS_F32 ].pipeline; break;
                        case GGML_TYPE_IQ2_K:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ2_K_F32  ].pipeline; break;
                        case GGML_TYPE_IQ2_KS:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ2_KS_F32 ].pipeline; break;
                        case GGML_TYPE_IQ2_KL:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ2_KL_F32 ].pipeline; break;
                        case GGML_TYPE_IQ3_K:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ3_K_F32  ].pipeline; break;
                        case GGML_TYPE_IQ4_K:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ4_K_F32  ].pipeline; break;
                        case GGML_TYPE_IQ5_K:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ5_K_F32  ].pipeline; break;
                        case GGML_TYPE_IQ6_K:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ6_K_F32  ].pipeline; break;
                        case GGML_TYPE_IQ2_KT:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ2_KT_F32 ].pipeline; break;
                        case GGML_TYPE_IQ3_KT:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ3_KT_F32 ].pipeline; break;
                        //case GGML_TYPE_IQ4_KT:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MM_ID_IQ4_KT_F32 ].pipeline; break;
                        default: GGML_ABORT("MUL_MAT_ID not implemented");
                    }

                    [encoder setComputePipelineState:pipeline];
                    [encoder setBuffer:id_src0 offset:offs_src0    atIndex:0];
                    [encoder setBuffer:id_src1 offset:offs_src1    atIndex:1];
                    [encoder setBuffer:id_dst  offset:offs_dst     atIndex:2];
                    [encoder setBuffer:id_src2 offset:offs_src2    atIndex:3];
                    [encoder setBytes:&ne20    length:sizeof(ne20) atIndex:4];
                    [encoder setBytes:&ne21    length:sizeof(ne21) atIndex:5];
                    [encoder setBytes:&nb21    length:sizeof(nb21) atIndex:6];
                    [encoder setBytes:&ne00    length:sizeof(ne00) atIndex:7];
                    [encoder setBytes:&ne02    length:sizeof(ne02) atIndex:8];
                    [encoder setBytes:&nb01    length:sizeof(nb01) atIndex:9];
                    [encoder setBytes:&nb02    length:sizeof(nb02) atIndex:10];
                    [encoder setBytes:&ne11    length:sizeof(ne11) atIndex:11];
                    [encoder setBytes:&ne12    length:sizeof(ne12) atIndex:12];
                    [encoder setBytes:&ne13    length:sizeof(ne13) atIndex:13];
                    [encoder setBytes:&nb10    length:sizeof(nb10) atIndex:14];
                    [encoder setBytes:&nb11    length:sizeof(nb11) atIndex:15];
                    [encoder setBytes:&nb12    length:sizeof(nb12) atIndex:16];
                    [encoder setBytes:&ne0     length:sizeof(ne0)  atIndex:17];
                    [encoder setBytes:&ne1     length:sizeof(ne1)  atIndex:18];
                    [encoder setBytes:&nb1     length:sizeof(nb1)  atIndex:19];

                    [encoder setThreadgroupMemoryLength:GGML_PAD(8192 + dst_rows*4/*sizeof(ushort2)*/, 16) atIndex:0];

                    [encoder dispatchThreadgroups:MTLSizeMake(1, (ne01 + 63)/64, n_as) threadsPerThreadgroup:MTLSizeMake(128, 1, 1)];

                } else {
                    int nth0 = 32;
                    int nth1 = 1;
                    int nrows = 1;

                    id<MTLComputePipelineState> pipeline = nil;

                    // use custom matrix x vector kernel
                    switch (src0t) {
                        case GGML_TYPE_F32:
                            {
                                GGML_ASSERT(src1t == GGML_TYPE_F32);
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_F32_F32].pipeline;
                            } break;
                        case GGML_TYPE_F16:
                            {
                                GGML_ASSERT(src1t == GGML_TYPE_F32);
                                nth0 = 32;
                                nth1 = 1;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_F16_F32].pipeline;
                            } break;
                        case GGML_TYPE_BF16:
                            {
                                GGML_ASSERT(src1t == GGML_TYPE_F32);
                                nth0 = 32;
                                nth1 = 1;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_BF16_F32].pipeline;
                            } break;
                        case GGML_TYPE_Q4_0:
                            {
                                nth0 = 8;
                                nth1 = 8;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q4_0_F32].pipeline;
                            } break;
                        case GGML_TYPE_Q4_1:
                            {
                                nth0 = 8;
                                nth1 = 8;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q4_1_F32].pipeline;
                            } break;
                        case GGML_TYPE_Q5_0:
                            {
                                nth0 = 8;
                                nth1 = 8;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q5_0_F32].pipeline;
                            } break;
                        case GGML_TYPE_Q5_1:
                            {
                                nth0 = 8;
                                nth1 = 8;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q5_1_F32].pipeline;
                            } break;
                        case GGML_TYPE_Q6_0:
                            {
                                nth0 = 8;
                                nth1 = 8;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q6_0_F32].pipeline;
                            } break;
                        case GGML_TYPE_Q8_0:
                            {
                                nth0 = 32;
                                nth1 = 2;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q8_0_F32].pipeline;
                            } break;
                        case GGML_TYPE_Q2_K:
                            {
                                nth0 = 2;
                                nth1 = 32;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q2_K_F32].pipeline;
                            } break;
                        case GGML_TYPE_Q3_K:
                            {
                                nth0 = 2;
                                nth1 = 32;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q3_K_F32].pipeline;
                            } break;
                        case GGML_TYPE_Q4_K:
                            {
                                nth0 = 4; //1;
                                nth1 = 8; //32;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q4_K_F32].pipeline;
                            } break;
                        case GGML_TYPE_Q5_K:
                            {
                                nth0 = 2;
                                nth1 = 32;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q5_K_F32].pipeline;
                            } break;
                        case GGML_TYPE_Q6_K:
                            {
                                nth0 = 2;
                                nth1 = 32;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_Q6_K_F32].pipeline;
                            } break;
                        case GGML_TYPE_IQ2_XXS:
                            {
                                nth0 = 4;
                                nth1 = 16;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ2_XXS_F32].pipeline;
                            } break;
                        case GGML_TYPE_IQ2_XS:
                            {
                                nth0 = 4;
                                nth1 = 16;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ2_XS_F32].pipeline;
                            } break;
                        case GGML_TYPE_IQ3_XXS:
                            {
                                nth0 = 4;
                                nth1 = 16;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ3_XXS_F32].pipeline;
                            } break;
                        case GGML_TYPE_IQ3_S:
                            {
                                nth0 = 4;
                                nth1 = 16;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ3_S_F32].pipeline;
                            } break;
                        case GGML_TYPE_IQ2_S:
                            {
                                nth0 = 4;
                                nth1 = 16;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ2_S_F32].pipeline;
                            } break;
                        case GGML_TYPE_IQ1_S:
                            {
                                nth0 = 4;
                                nth1 = 16;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ1_S_F32].pipeline;
                            } break;
                        case GGML_TYPE_IQ1_M:
                            {
                                nth0 = 4;
                                nth1 = 16;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ1_M_F32].pipeline;
                            } break;
                        case GGML_TYPE_IQ1_BN:
                            {
                                nth0 = 4;
                                nth1 = 16;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ1_BN_F32].pipeline;
                            } break;
                        case GGML_TYPE_IQ2_BN:
                            {
                                nth0 = 4;
                                nth1 = 16;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ2_BN_F32].pipeline;
                            } break;
                        case GGML_TYPE_IQ4_NL:
                            {
                                nth0 = 32;
                                nth1 = 2;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ4_NL_F32].pipeline;
                            } break;
                        case GGML_TYPE_IQ4_XS:
                            {
                                nth0 = 32;
                                nth1 = 2;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ4_XS_F32].pipeline;
                            } break;
                        case GGML_TYPE_IQ3_KS:
                            {
                                nth0 = 4;
                                nth1 = 16;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ3_KS_F32].pipeline;
                            } break;
                        case GGML_TYPE_IQ4_KS:
                            {
                                nth0 = 4;
                                nth1 = 16;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ4_KS_F32].pipeline;
                            } break;
                        case GGML_TYPE_IQ4_KSS:
                            {
                                nth0 = 4;
                                nth1 = 16;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ4_KSS_F32].pipeline;
                            } break;
                        case GGML_TYPE_IQ5_KS:
                            {
                                nth0 = 4;
                                nth1 = 16;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ5_KS_F32].pipeline;
                            } break;
                        case GGML_TYPE_IQ2_K:
                            {
                                nth0 = 4;
                                nth1 = 16;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ2_K_F32].pipeline;
                            } break;
                        case GGML_TYPE_IQ2_KS:
                            {
                                nth0 = 4;
                                nth1 = 16;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ2_KS_F32].pipeline;
                            } break;
                        case GGML_TYPE_IQ2_KL:
                            {
                                nth0 = 4;
                                nth1 = 16;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ2_KL_F32].pipeline;
                            } break;
                        case GGML_TYPE_IQ3_K:
                            {
                                nth0 = 4;
                                nth1 = 16;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ3_K_F32].pipeline;
                            } break;
                        case GGML_TYPE_IQ4_K:
                            {
                                nth0 = 4;
                                nth1 = 16;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ4_K_F32].pipeline;
                            } break;
                        case GGML_TYPE_IQ5_K:
                            {
                                nth0 = 4;
                                nth1 = 16;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ5_K_F32].pipeline;
                            } break;
                        case GGML_TYPE_IQ6_K:
                            {
                                nth0 = 4;
                                nth1 = 16;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ6_K_F32].pipeline;
                            } break;
                        case GGML_TYPE_IQ2_KT:
                            {
                                nth0 = 4;
                                nth1 = 16;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ2_KT_F32].pipeline;
                            } break;
                        case GGML_TYPE_IQ3_KT:
                            {
                                nth0 = 4;
                                nth1 = 16;
                                pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ3_KT_F32].pipeline;
                            } break;
                        //case GGML_TYPE_IQ4_KT:
                        //    {
                        //        nth0 = 4;
                        //        nth1 = 16;
                        //        pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_MUL_MV_ID_IQ4_KT_F32].pipeline;
                        //    } break;
                        default:
                            {
                                GGML_METAL_LOG_ERROR("Asserting on type %d\n", (int)src2t);
                                GGML_ABORT("not implemented");
                            }
                    };

                    if (ggml_is_quantized(src0t)) {
                        GGML_ASSERT(ne00 >= nth0*nth1);
                    }

                    [encoder setComputePipelineState:pipeline];
                    [encoder setBuffer:id_src0 offset:offs_src0 atIndex:0];
                    [encoder setBuffer:id_src1 offset:offs_src1 atIndex:1];
                    [encoder setBuffer:id_dst  offset:offs_dst  atIndex:2];
                    [encoder setBuffer:id_src2 offset:offs_src2 atIndex:3];
                    [encoder setBytes:&ne20 length:sizeof(ne20) atIndex:4];
                    [encoder setBytes:&ne21 length:sizeof(ne21) atIndex:5];
                    [encoder setBytes:&nb21 length:sizeof(nb21) atIndex:6];
                    [encoder setBytes:&ne00 length:sizeof(ne00) atIndex:7];
                    [encoder setBytes:&ne01 length:sizeof(ne01) atIndex:8];
                    [encoder setBytes:&ne02 length:sizeof(ne02) atIndex:9];
                    [encoder setBytes:&nb00 length:sizeof(nb00) atIndex:10];
                    [encoder setBytes:&nb01 length:sizeof(nb01) atIndex:11];
                    [encoder setBytes:&nb02 length:sizeof(nb02) atIndex:12];
                    [encoder setBytes:&ne10 length:sizeof(ne10) atIndex:13];
                    [encoder setBytes:&ne11 length:sizeof(ne11) atIndex:14];
                    [encoder setBytes:&ne12 length:sizeof(ne12) atIndex:15];
                    [encoder setBytes:&ne13 length:sizeof(ne13) atIndex:16];
                    [encoder setBytes:&nb10 length:sizeof(nb10) atIndex:17];
                    [encoder setBytes:&nb11 length:sizeof(nb11) atIndex:18];
                    [encoder setBytes:&nb12 length:sizeof(nb12) atIndex:19];
                    [encoder setBytes:&ne0  length:sizeof(ne0)  atIndex:20];
                    [encoder setBytes:&ne1  length:sizeof(ne1)  atIndex:21];
                    [encoder setBytes:&nb1  length:sizeof(nb1)  atIndex:22];

                    const int64_t _ne1 = 1;
                    const int tgz = dst_rows;

                    if (src0t == GGML_TYPE_Q4_0  || src0t == GGML_TYPE_Q4_1  || src0t == GGML_TYPE_Q5_0 ||
                            src0t == GGML_TYPE_Q5_1  || src0t == GGML_TYPE_Q8_0  || src0t == GGML_TYPE_Q2_K ||
                            src0t == GGML_TYPE_IQ1_S || src0t == GGML_TYPE_IQ1_M || src0t == GGML_TYPE_Q6_0 ||
                            src0t == GGML_TYPE_IQ1_BN|| src0t == GGML_TYPE_IQ2_BN|| src0t == GGML_TYPE_IQ2_K||
                            src0t == GGML_TYPE_IQ2_KT|| src0t == GGML_TYPE_IQ3_KT) { //|| src0t == GGML_TYPE_IQ4_KT) {
                        [encoder dispatchThreadgroups:MTLSizeMake((ne01 + 7)/8, _ne1, tgz) threadsPerThreadgroup:MTLSizeMake(nth0, nth1, 1)];
                    }
                    else if (src0t == GGML_TYPE_IQ2_KS || src0t == GGML_TYPE_IQ2_K || src0t == GGML_TYPE_IQ3_K || src0t == GGML_TYPE_IQ3_KS ||
                             src0t == GGML_TYPE_IQ2_KL) {
                        const int mem_size = src0t == GGML_TYPE_IQ2_KL ? 128*sizeof(float)
                                           : src0t == GGML_TYPE_IQ2_KS ? 64*sizeof(float)
                                           : src0t == GGML_TYPE_IQ3_K || src0t == GGML_TYPE_IQ3_KS ? 32*sizeof(float) : 16*sizeof(float);
                        [encoder setThreadgroupMemoryLength:mem_size atIndex:0];
                        [encoder dispatchThreadgroups:MTLSizeMake((ne01 + 7)/8, _ne1, tgz) threadsPerThreadgroup:MTLSizeMake(nth0, nth1, 1)];
                    }
                    else if (src0t == GGML_TYPE_IQ2_XXS || src0t == GGML_TYPE_IQ2_XS) {
                        const int mem_size = src0t == GGML_TYPE_IQ2_XXS ? 256*8+128 : 512*8+128;
                        [encoder setThreadgroupMemoryLength:mem_size atIndex:0];
                        [encoder dispatchThreadgroups:MTLSizeMake((ne01 + 7)/8, _ne1, tgz) threadsPerThreadgroup:MTLSizeMake(nth0, nth1, 1)];
                    }
                    else if (src0t == GGML_TYPE_IQ3_XXS || src0t == GGML_TYPE_IQ3_S) {
                        const int mem_size = src0t == GGML_TYPE_IQ3_XXS ? 256*4+128 : 512*4;
                        [encoder setThreadgroupMemoryLength:mem_size atIndex:0];
                        [encoder dispatchThreadgroups:MTLSizeMake((ne01 + 7)/8, _ne1, tgz) threadsPerThreadgroup:MTLSizeMake(nth0, nth1, 1)];
                    }
                    else if (src0t == GGML_TYPE_IQ4_NL || src0t == GGML_TYPE_IQ4_XS || src0t == GGML_TYPE_IQ4_K ||
                            src0t == GGML_TYPE_IQ5_K  || src0t == GGML_TYPE_IQ6_K  || src0t == GGML_TYPE_IQ4_KS||
                            src0t == GGML_TYPE_IQ4_KSS || src0t == GGML_TYPE_IQ5_KS) {
                        const int mem_size = src0t == GGML_TYPE_IQ6_K ? 128*sizeof(float)
                            : src0t == GGML_TYPE_IQ5_K || src0t == GGML_TYPE_IQ5_KS ? 64*sizeof(float) : 32*sizeof(float);
                        [encoder setThreadgroupMemoryLength:mem_size atIndex:0];
                        [encoder dispatchThreadgroups:MTLSizeMake((ne01 + 3)/4, _ne1, tgz) threadsPerThreadgroup:MTLSizeMake(nth0, nth1, 1)];
                    }
                    else if (src0t == GGML_TYPE_Q4_K) {
                        [encoder dispatchThreadgroups:MTLSizeMake((ne01 + 3)/4, _ne1, tgz) threadsPerThreadgroup:MTLSizeMake(nth0, nth1, 1)];
                    }
                    else if (src0t == GGML_TYPE_Q3_K) {
                        [encoder dispatchThreadgroups:MTLSizeMake((ne01 + 3)/4, _ne1, tgz) threadsPerThreadgroup:MTLSizeMake(nth0, nth1, 1)];
                    }
                    else if (src0t == GGML_TYPE_Q5_K) {
                        [encoder dispatchThreadgroups:MTLSizeMake((ne01 + 3)/4, _ne1, tgz) threadsPerThreadgroup:MTLSizeMake(nth0, nth1, 1)];
                    }
                    else if (src0t == GGML_TYPE_Q6_K) {
                        [encoder dispatchThreadgroups:MTLSizeMake((ne01 + 1)/2, _ne1, tgz) threadsPerThreadgroup:MTLSizeMake(nth0, nth1, 1)];
                    } else {
                        const int64_t ny = (_ne1 + nrows - 1)/nrows; // = _ne1
                        [encoder dispatchThreadgroups:MTLSizeMake(ne01, ny, tgz) threadsPerThreadgroup:MTLSizeMake(nth0, nth1, 1)];
                    }
                }
            } break;
        case GGML_OP_GET_ROWS:
            {
                id<MTLComputePipelineState> pipeline = nil;

                switch (src0->type) {
                    case GGML_TYPE_F32:     pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_F32    ].pipeline; break;
                    case GGML_TYPE_F16:     pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_F16    ].pipeline; break;
                    case GGML_TYPE_Q4_0:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_Q4_0   ].pipeline; break;
                    case GGML_TYPE_Q4_1:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_Q4_1   ].pipeline; break;
                    case GGML_TYPE_Q5_0:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_Q5_0   ].pipeline; break;
                    case GGML_TYPE_Q5_1:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_Q5_1   ].pipeline; break;
                    case GGML_TYPE_Q6_0:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_Q6_0   ].pipeline; break;
                    case GGML_TYPE_Q8_0:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_Q8_0   ].pipeline; break;
                    case GGML_TYPE_Q2_K:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_Q2_K   ].pipeline; break;
                    case GGML_TYPE_Q3_K:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_Q3_K   ].pipeline; break;
                    case GGML_TYPE_Q4_K:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_Q4_K   ].pipeline; break;
                    case GGML_TYPE_Q5_K:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_Q5_K   ].pipeline; break;
                    case GGML_TYPE_Q6_K:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_Q6_K   ].pipeline; break;
                    case GGML_TYPE_IQ2_XXS: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ2_XXS].pipeline; break;
                    case GGML_TYPE_IQ2_XS:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ2_XS ].pipeline; break;
                    case GGML_TYPE_IQ3_XXS: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ3_XXS].pipeline; break;
                    case GGML_TYPE_IQ3_S:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ3_S  ].pipeline; break;
                    case GGML_TYPE_IQ2_S:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ2_S  ].pipeline; break;
                    case GGML_TYPE_IQ1_S:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ1_S  ].pipeline; break;
                    case GGML_TYPE_IQ1_M:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ1_M  ].pipeline; break;
                    case GGML_TYPE_IQ1_BN:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ1_BN ].pipeline; break;
                    case GGML_TYPE_IQ2_BN:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ2_BN ].pipeline; break;
                    case GGML_TYPE_IQ4_NL:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ4_NL ].pipeline; break;
                    case GGML_TYPE_IQ4_XS:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ4_XS ].pipeline; break;
                    case GGML_TYPE_IQ3_KS:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ3_KS ].pipeline; break;
                    case GGML_TYPE_IQ4_KS:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ4_KS ].pipeline; break;
                    case GGML_TYPE_IQ4_KSS: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ4_KSS].pipeline; break;
                    case GGML_TYPE_IQ5_KS:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ5_KS ].pipeline; break;
                    case GGML_TYPE_IQ2_K:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ2_K  ].pipeline; break;
                    case GGML_TYPE_IQ2_KS:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ2_KS ].pipeline; break;
                    case GGML_TYPE_IQ2_KL:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ2_KL ].pipeline; break;
                    case GGML_TYPE_IQ3_K:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ3_K  ].pipeline; break;
                    case GGML_TYPE_IQ4_K:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ4_K  ].pipeline; break;
                    case GGML_TYPE_IQ5_K:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ5_K  ].pipeline; break;
                    case GGML_TYPE_IQ6_K:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ6_K  ].pipeline; break;
                    case GGML_TYPE_IQ2_KT:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ2_KT ].pipeline; break;
                    case GGML_TYPE_IQ3_KT:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ3_KT ].pipeline; break;
                    //case GGML_TYPE_IQ4_KT:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_IQ4_KT ].pipeline; break;
                    case GGML_TYPE_I32:     pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GET_ROWS_I32    ].pipeline; break;
                    default: GGML_ABORT("not implemented");
                }

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0     offset:offs_src0 atIndex:0];
                [encoder setBuffer:id_src1     offset:offs_src1 atIndex:1];
                [encoder setBuffer:id_dst      offset:offs_dst  atIndex:2];
                [encoder setBytes:&ne00 length:sizeof( int64_t) atIndex:3];
                [encoder setBytes:&nb01 length:sizeof(uint64_t) atIndex:4];
                [encoder setBytes:&nb02 length:sizeof(uint64_t) atIndex:5];
                [encoder setBytes:&ne10 length:sizeof( int64_t) atIndex:6];
                [encoder setBytes:&nb10 length:sizeof( int64_t) atIndex:7];
                [encoder setBytes:&nb11 length:sizeof( int64_t) atIndex:8];
                [encoder setBytes:&nb1  length:sizeof(uint64_t) atIndex:9];
                [encoder setBytes:&nb2  length:sizeof(uint64_t) atIndex:10];

                [encoder dispatchThreadgroups:MTLSizeMake(ne10, ne11, 1) threadsPerThreadgroup:MTLSizeMake(32, 1, 1)];
            } break;
        case GGML_OP_RMS_NORM:
            {
                GGML_ASSERT(ne00 % 4 == 0);
                GGML_ASSERT(ggml_is_contiguous_1(src0));

                float eps;
                memcpy(&eps, dst->op_params, sizeof(float));

                int nth = 32; // SIMD width

                while (nth < ne00/4 && nth < 1024) {
                    nth *= 2;
                }

                nth = MIN(nth, ne00/4);

                id<MTLComputePipelineState> pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_RMS_NORM].pipeline;

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0 offset:offs_src0        atIndex:0];
                [encoder setBuffer:id_dst  offset:offs_dst         atIndex:1];
                [encoder setBytes:&ne00    length:sizeof( int64_t) atIndex:2];
                [encoder setBytes:&nb01    length:sizeof(uint64_t) atIndex:3];
                [encoder setBytes:&eps     length:sizeof(   float) atIndex:4];
                [encoder setThreadgroupMemoryLength:32*sizeof(float) atIndex:0];

                const int64_t nrows = ggml_nrows(src0);

                [encoder dispatchThreadgroups:MTLSizeMake(nrows, 1, 1) threadsPerThreadgroup:MTLSizeMake(nth, 1, 1)];
            } break;
        case GGML_OP_FUSED_RMS_NORM:
            {
                GGML_ASSERT(ne00 % 4 == 0);
                GGML_ASSERT(ggml_is_contiguous_1(src0));
                GGML_ASSERT(src1->ne[0] == src0->ne[0]);
                GGML_ASSERT(src1->type  == GGML_TYPE_F32);
                GGML_ASSERT(ggml_nrows(src1) == 1);

                float eps;
                memcpy(&eps, dst->op_params, sizeof(float));

                int nth = 32; // SIMD width

                while (nth < ne00/4 && nth < 1024) {
                    nth *= 2;
                }

                nth = MIN(nth, ne00/4);

                id<MTLComputePipelineState> pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FUSED_RMS_NORM].pipeline;

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0 offset:offs_src0        atIndex:0];
                [encoder setBuffer:id_src1 offset:offs_src1        atIndex:1];
                [encoder setBuffer:id_dst  offset:offs_dst         atIndex:2];
                [encoder setBytes:&ne00    length:sizeof( int64_t) atIndex:3];
                [encoder setBytes:&nb01    length:sizeof(uint64_t) atIndex:4];
                [encoder setBytes:&eps     length:sizeof(   float) atIndex:5];
                [encoder setThreadgroupMemoryLength:32*sizeof(float) atIndex:0];

                const int64_t nrows = ggml_nrows(src0);

                [encoder dispatchThreadgroups:MTLSizeMake(nrows, 1, 1) threadsPerThreadgroup:MTLSizeMake(nth, 1, 1)];
            } break;
        case GGML_OP_GROUP_NORM:
            {
                GGML_ASSERT(ne00 % 4 == 0);
                GGML_ASSERT(ggml_is_contiguous(src0));

                float eps;
                memcpy(&eps, dst->op_params + 1, sizeof(float));

                const int32_t n_groups = ((int32_t *) dst->op_params)[0];

                int nth = 32; // SIMD width

                //while (nth < ne00/4 && nth < 1024) {
                //    nth *= 2;
                //}

                id<MTLComputePipelineState> pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_GROUP_NORM].pipeline;

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0  offset:offs_src0        atIndex:0];
                [encoder setBuffer:id_dst   offset:offs_dst         atIndex:1];
                [encoder setBytes:&ne00     length:sizeof( int64_t) atIndex:2];
                [encoder setBytes:&ne01     length:sizeof( int64_t) atIndex:3];
                [encoder setBytes:&ne02     length:sizeof( int64_t) atIndex:4];
                [encoder setBytes:&nb00     length:sizeof(uint64_t) atIndex:5];
                [encoder setBytes:&nb01     length:sizeof(uint64_t) atIndex:6];
                [encoder setBytes:&nb02     length:sizeof(uint64_t) atIndex:7];
                [encoder setBytes:&n_groups length:sizeof( int32_t) atIndex:8];
                [encoder setBytes:&eps      length:sizeof(   float) atIndex:9];
                [encoder setThreadgroupMemoryLength:32*sizeof(float) atIndex:0];

                [encoder dispatchThreadgroups:MTLSizeMake(n_groups, 1, 1) threadsPerThreadgroup:MTLSizeMake(nth, 1, 1)];
            } break;
        case GGML_OP_NORM:
            {
                GGML_ASSERT(ggml_is_contiguous_1(src0));

                float eps;
                memcpy(&eps, dst->op_params, sizeof(float));

                const int nth = MIN(256, ne00);

                id<MTLComputePipelineState> pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_NORM].pipeline;

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0 offset:offs_src0        atIndex:0];
                [encoder setBuffer:id_dst  offset:offs_dst         atIndex:1];
                [encoder setBytes:&ne00    length:sizeof( int64_t) atIndex:2];
                [encoder setBytes:&nb01    length:sizeof(uint64_t) atIndex:3];
                [encoder setBytes:&eps     length:sizeof(   float) atIndex:4];
                [encoder setThreadgroupMemoryLength:GGML_PAD(nth*sizeof(float), 16) atIndex:0];

                const int64_t nrows = ggml_nrows(src0);

                [encoder dispatchThreadgroups:MTLSizeMake(nrows, 1, 1) threadsPerThreadgroup:MTLSizeMake(nth, 1, 1)];
            } break;
        case GGML_OP_ROPE:
            {
                GGML_ASSERT(ne10 == ne02);

                const int nth = MIN(1024, ne00);

                const int n_past     = ((int32_t *) dst->op_params)[0];
                const int n_dims     = ((int32_t *) dst->op_params)[1];
                const int mode       = ((int32_t *) dst->op_params)[2];
                // skip 3, n_ctx, used in GLM RoPE, unimplemented in metal
                const int n_ctx_orig = ((int32_t *) dst->op_params)[4];

                float freq_base;
                float freq_scale;
                float ext_factor;
                float attn_factor;
                float beta_fast;
                float beta_slow;

                memcpy(&freq_base,   (int32_t *) dst->op_params +  5, sizeof(float));
                memcpy(&freq_scale,  (int32_t *) dst->op_params +  6, sizeof(float));
                memcpy(&ext_factor,  (int32_t *) dst->op_params +  7, sizeof(float));
                memcpy(&attn_factor, (int32_t *) dst->op_params +  8, sizeof(float));
                memcpy(&beta_fast,   (int32_t *) dst->op_params +  9, sizeof(float));
                memcpy(&beta_slow,   (int32_t *) dst->op_params + 10, sizeof(float));

                const bool is_neox = mode & 2;

                id<MTLComputePipelineState> pipeline = nil;

                if (!is_neox) {
                    switch (src0->type) {
                        case GGML_TYPE_F32: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_ROPE_NORM_F32].pipeline; break;
                        case GGML_TYPE_F16: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_ROPE_NORM_F16].pipeline; break;
                        default: GGML_ABORT("fatal error");
                    };
                } else {
                    switch (src0->type) {
                        case GGML_TYPE_F32: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_ROPE_NEOX_F32].pipeline; break;
                        case GGML_TYPE_F16: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_ROPE_NEOX_F16].pipeline; break;
                        default: GGML_ABORT("fatal error");
                    };
                }

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0     offset:offs_src0        atIndex:0];
                [encoder setBuffer:id_src1     offset:offs_src1        atIndex:1];
                if (id_src2 != nil) {
                    [encoder setBuffer:id_src2 offset:offs_src2        atIndex:2];
                } else {
                    [encoder setBuffer:id_src0 offset:offs_src0        atIndex:2];
                }
                [encoder setBuffer:id_dst      offset:offs_dst         atIndex:3];
                [encoder setBytes:&ne00        length:sizeof( int64_t) atIndex:4];
                [encoder setBytes:&ne01        length:sizeof( int64_t) atIndex:5];
                [encoder setBytes:&ne02        length:sizeof( int64_t) atIndex:6];
                [encoder setBytes:&ne03        length:sizeof( int64_t) atIndex:7];
                [encoder setBytes:&nb00        length:sizeof(uint64_t) atIndex:8];
                [encoder setBytes:&nb01        length:sizeof(uint64_t) atIndex:9];
                [encoder setBytes:&nb02        length:sizeof(uint64_t) atIndex:10];
                [encoder setBytes:&nb03        length:sizeof(uint64_t) atIndex:11];
                [encoder setBytes:&ne0         length:sizeof( int64_t) atIndex:12];
                [encoder setBytes:&ne1         length:sizeof( int64_t) atIndex:13];
                [encoder setBytes:&ne2         length:sizeof( int64_t) atIndex:14];
                [encoder setBytes:&ne3         length:sizeof( int64_t) atIndex:15];
                [encoder setBytes:&nb0         length:sizeof(uint64_t) atIndex:16];
                [encoder setBytes:&nb1         length:sizeof(uint64_t) atIndex:17];
                [encoder setBytes:&nb2         length:sizeof(uint64_t) atIndex:18];
                [encoder setBytes:&nb3         length:sizeof(uint64_t) atIndex:19];
                [encoder setBytes:&n_past      length:sizeof(     int) atIndex:20];
                [encoder setBytes:&n_dims      length:sizeof(     int) atIndex:21];
                [encoder setBytes:&n_ctx_orig  length:sizeof(     int) atIndex:22];
                [encoder setBytes:&freq_base   length:sizeof(   float) atIndex:23];
                [encoder setBytes:&freq_scale  length:sizeof(   float) atIndex:24];
                [encoder setBytes:&ext_factor  length:sizeof(   float) atIndex:25];
                [encoder setBytes:&attn_factor length:sizeof(   float) atIndex:26];
                [encoder setBytes:&beta_fast   length:sizeof(   float) atIndex:27];
                [encoder setBytes:&beta_slow   length:sizeof(   float) atIndex:28];

                [encoder dispatchThreadgroups:MTLSizeMake(ne01, ne02, ne03) threadsPerThreadgroup:MTLSizeMake(nth, 1, 1)];
            } break;
        case GGML_OP_IM2COL:
            {
                GGML_ASSERT(src0->type == GGML_TYPE_F16);
                GGML_ASSERT(src1->type == GGML_TYPE_F32);
                GGML_ASSERT( dst->type == GGML_TYPE_F16 || dst->type == GGML_TYPE_F32);

                const int32_t s0 = ((const int32_t *)(dst->op_params))[0];
                const int32_t s1 = ((const int32_t *)(dst->op_params))[1];
                const int32_t p0 = ((const int32_t *)(dst->op_params))[2];
                const int32_t p1 = ((const int32_t *)(dst->op_params))[3];
                const int32_t d0 = ((const int32_t *)(dst->op_params))[4];
                const int32_t d1 = ((const int32_t *)(dst->op_params))[5];

                const bool is_2D = ((const int32_t *)(dst->op_params))[6] == 1;

                const int32_t N  = src1->ne[is_2D ? 3 : 2];
                const int32_t IC = src1->ne[is_2D ? 2 : 1];
                const int32_t IH = is_2D ? src1->ne[1] : 1;
                const int32_t IW =         src1->ne[0];

                const int32_t KH = is_2D ? src0->ne[1] : 1;
                const int32_t KW =         src0->ne[0];

                const int32_t OH = is_2D ? dst->ne[2] : 1;
                const int32_t OW =         dst->ne[1];

                const int32_t CHW = IC * KH * KW;

                const int32_t ofs0 = src1->nb[is_2D ? 3 : 2] / 4;
                const int32_t ofs1 = src1->nb[is_2D ? 2 : 1] / 4;

                id<MTLComputePipelineState> pipeline = nil;

                switch (dst->type) {
                    case GGML_TYPE_F32: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_IM2COL_F32].pipeline; break;
                    case GGML_TYPE_F16: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_IM2COL_F16].pipeline; break;
                    default: GGML_ABORT("fatal error");
                };

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src1 offset:offs_src1        atIndex:0];
                [encoder setBuffer:id_dst  offset:offs_dst         atIndex:1];
                [encoder setBytes:&ofs0    length:sizeof( int32_t) atIndex:2];
                [encoder setBytes:&ofs1    length:sizeof( int32_t) atIndex:3];
                [encoder setBytes:&IW      length:sizeof( int32_t) atIndex:4];
                [encoder setBytes:&IH      length:sizeof( int32_t) atIndex:5];
                [encoder setBytes:&CHW     length:sizeof( int32_t) atIndex:6];
                [encoder setBytes:&s0      length:sizeof( int32_t) atIndex:7];
                [encoder setBytes:&s1      length:sizeof( int32_t) atIndex:8];
                [encoder setBytes:&p0      length:sizeof( int32_t) atIndex:9];
                [encoder setBytes:&p1      length:sizeof( int32_t) atIndex:10];
                [encoder setBytes:&d0      length:sizeof( int32_t) atIndex:11];
                [encoder setBytes:&d1      length:sizeof( int32_t) atIndex:12];

                [encoder dispatchThreadgroups:MTLSizeMake(IC, OH, OW) threadsPerThreadgroup:MTLSizeMake(N, KH, KW)];
            } break;
        case GGML_OP_UPSCALE:
            {
                GGML_ASSERT(src0->type == GGML_TYPE_F32);

                const float sf0 = (float)ne0/src0->ne[0];
                const float sf1 = (float)ne1/src0->ne[1];
                const float sf2 = (float)ne2/src0->ne[2];
                const float sf3 = (float)ne3/src0->ne[3];

                const id<MTLComputePipelineState> pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_UPSCALE_F32].pipeline;

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0 offset:offs_src0 atIndex:0];
                [encoder setBuffer:id_dst  offset:offs_dst  atIndex:1];
                [encoder setBytes:&ne00 length:sizeof(ne00) atIndex:2];
                [encoder setBytes:&ne01 length:sizeof(ne01) atIndex:3];
                [encoder setBytes:&ne02 length:sizeof(ne02) atIndex:4];
                [encoder setBytes:&ne03 length:sizeof(ne03) atIndex:5];
                [encoder setBytes:&nb00 length:sizeof(nb00) atIndex:6];
                [encoder setBytes:&nb01 length:sizeof(nb01) atIndex:7];
                [encoder setBytes:&nb02 length:sizeof(nb02) atIndex:8];
                [encoder setBytes:&nb03 length:sizeof(nb03) atIndex:9];
                [encoder setBytes:&ne0  length:sizeof(ne0)  atIndex:10];
                [encoder setBytes:&ne1  length:sizeof(ne1)  atIndex:11];
                [encoder setBytes:&ne2  length:sizeof(ne2)  atIndex:12];
                [encoder setBytes:&ne3  length:sizeof(ne3)  atIndex:13];
                [encoder setBytes:&nb0  length:sizeof(nb0)  atIndex:14];
                [encoder setBytes:&nb1  length:sizeof(nb1)  atIndex:15];
                [encoder setBytes:&nb2  length:sizeof(nb2)  atIndex:16];
                [encoder setBytes:&nb3  length:sizeof(nb3)  atIndex:17];
                [encoder setBytes:&sf0  length:sizeof(sf0)  atIndex:18];
                [encoder setBytes:&sf1  length:sizeof(sf1)  atIndex:19];
                [encoder setBytes:&sf2  length:sizeof(sf2)  atIndex:20];
                [encoder setBytes:&sf3  length:sizeof(sf3)  atIndex:21];

                const int nth = MIN((int) pipeline.maxTotalThreadsPerThreadgroup, ne0);

                [encoder dispatchThreadgroups:MTLSizeMake(ne1, ne2, ne3) threadsPerThreadgroup:MTLSizeMake(nth, 1, 1)];
            } break;
        case GGML_OP_PAD:
            {
                GGML_ASSERT(src0->type == GGML_TYPE_F32);

                id<MTLComputePipelineState> pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_PAD_F32].pipeline;

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0 offset:offs_src0 atIndex:0];
                [encoder setBuffer:id_dst  offset:offs_dst  atIndex:1];
                [encoder setBytes:&ne00 length:sizeof(ne00) atIndex:2];
                [encoder setBytes:&ne01 length:sizeof(ne01) atIndex:3];
                [encoder setBytes:&ne02 length:sizeof(ne02) atIndex:4];
                [encoder setBytes:&ne03 length:sizeof(ne03) atIndex:5];
                [encoder setBytes:&nb00 length:sizeof(nb00) atIndex:6];
                [encoder setBytes:&nb01 length:sizeof(nb01) atIndex:7];
                [encoder setBytes:&nb02 length:sizeof(nb02) atIndex:8];
                [encoder setBytes:&nb03 length:sizeof(nb03) atIndex:9];
                [encoder setBytes:&ne0  length:sizeof(ne0)  atIndex:10];
                [encoder setBytes:&ne1  length:sizeof(ne1)  atIndex:11];
                [encoder setBytes:&ne2  length:sizeof(ne2)  atIndex:12];
                [encoder setBytes:&ne3  length:sizeof(ne3)  atIndex:13];
                [encoder setBytes:&nb0  length:sizeof(nb0)  atIndex:14];
                [encoder setBytes:&nb1  length:sizeof(nb1)  atIndex:15];
                [encoder setBytes:&nb2  length:sizeof(nb2)  atIndex:16];
                [encoder setBytes:&nb3  length:sizeof(nb3)  atIndex:17];

                const int nth = MIN(1024, ne0);

                [encoder dispatchThreadgroups:MTLSizeMake(ne1, ne2, ne3) threadsPerThreadgroup:MTLSizeMake(nth, 1, 1)];
            } break;
        case GGML_OP_ARANGE:
            {
                GGML_ASSERT(dst->type == GGML_TYPE_F32);

                float start;
                float step;

                memcpy(&start, ((int32_t *) dst->op_params) + 0, sizeof(float));
                memcpy(&step,  ((int32_t *) dst->op_params) + 2, sizeof(float));

                id<MTLComputePipelineState> pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_ARANGE_F32].pipeline;

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_dst  offset:offs_dst    atIndex:0];
                [encoder setBytes:&ne0   length:sizeof(ne0)   atIndex:1];
                [encoder setBytes:&start length:sizeof(start) atIndex:2];
                [encoder setBytes:&step  length:sizeof(step)  atIndex:3];

                const int nth = MIN(1024, ne0);

                [encoder dispatchThreadgroups:MTLSizeMake(1, 1, 1) threadsPerThreadgroup:MTLSizeMake(nth, 1, 1)];
            } break;
        case GGML_OP_TIMESTEP_EMBEDDING:
            {
                GGML_ASSERT(src0->type == GGML_TYPE_F32);

                const int dim        = dst->op_params[0];
                const int max_period = dst->op_params[1];

                const int half = dim / 2;

                id<MTLComputePipelineState> pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_TIMESTEP_EMBEDDING_F32].pipeline;

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0 offset:offs_src0 atIndex:0];
                [encoder setBuffer:id_dst  offset:offs_dst  atIndex:1];
                [encoder setBytes:&nb1   length:sizeof(nb1) atIndex:2];
                [encoder setBytes:&dim   length:sizeof(dim) atIndex:3];
                [encoder setBytes:&max_period length:sizeof(max_period) atIndex:4];

                const int nth = MIN(1024, half);

                [encoder dispatchThreadgroups:MTLSizeMake(ne00, 1, 1) threadsPerThreadgroup:MTLSizeMake(nth, 1, 1)];
            } break;
        case GGML_OP_ARGSORT:
            {
                GGML_ASSERT(src0->type == GGML_TYPE_F32);
                GGML_ASSERT( dst->type == GGML_TYPE_I32);

                const int nrows = ggml_nrows(src0);

                enum ggml_sort_order order = (enum ggml_sort_order) dst->op_params[0];

                // bitonic sort requires the number of elements to be power of 2
                int64_t ne00_padded = 1;
                while (ne00_padded < ne00) {
                    ne00_padded *= 2;
                }

                // Metal kernels require the buffer size to be multiple of 16 bytes
                // https://developer.apple.com/documentation/metal/mtlcomputecommandencoder/1443142-setthreadgroupmemorylength
                const int mem_size = GGML_PAD(ne00_padded*sizeof(int32_t), 16);

                id<MTLComputePipelineState> pipeline = nil;

                switch (order) {
                    case GGML_SORT_ORDER_ASC:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_ARGSORT_F32_I32_ASC].pipeline;  break;
                    case GGML_SORT_ORDER_DESC: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_ARGSORT_F32_I32_DESC].pipeline; break;
                    default: GGML_ABORT("fatal error");
                };

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0     offset:offs_src0        atIndex:0];
                [encoder setBuffer:id_dst      offset:offs_dst         atIndex:1];
                [encoder setBytes:&ne00        length:sizeof( int64_t) atIndex:2];
                [encoder setBytes:&ne00_padded length:sizeof( int64_t) atIndex:3];
                [encoder setThreadgroupMemoryLength:mem_size atIndex:0];

                [encoder dispatchThreadgroups:MTLSizeMake(1, nrows, 1) threadsPerThreadgroup:MTLSizeMake(ne00_padded, 1, 1)];
            } break;
        case GGML_OP_LEAKY_RELU:
            {
                GGML_ASSERT(src0->type == GGML_TYPE_F32);

                float slope;
                memcpy(&slope, dst->op_params, sizeof(float));

                id<MTLComputePipelineState> pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_LEAKY_RELU_F32].pipeline;

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0 offset:offs_src0   atIndex:0];
                [encoder setBuffer:id_dst  offset:offs_dst    atIndex:1];
                [encoder setBytes:&slope length:sizeof(slope) atIndex:2];

                const int64_t n = ggml_nelements(dst);

                [encoder dispatchThreadgroups:MTLSizeMake(n, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
            } break;
        case GGML_OP_FLASH_ATTN_EXT:
            {
                GGML_ASSERT(ne00 % 4  == 0);
                GGML_ASSERT(ne11 % 32 == 0);

                GGML_ASSERT(src0->type == GGML_TYPE_F32);
                GGML_ASSERT(src1->type == src2->type);
                GGML_ASSERT(ne11 == ne21);
                GGML_ASSERT(ne12 == ne22);

                struct ggml_tensor * src3 = node->src[3];

                size_t offs_src3 = 0;

                id<MTLBuffer> id_src3 = src3 ? ggml_metal_get_buffer(src3, &offs_src3) : nil;

                GGML_ASSERT(!src3 || src3->type == GGML_TYPE_F16);
                GGML_ASSERT(!src3 || src3->ne[1] >= GGML_PAD(src0->ne[1], 8) &&
                        "the Flash-Attention Metal kernel requires the mask to be padded to 8 and at least n_queries big");

                const int64_t  ne30 = src3 ? src3->ne[0] : 0; GGML_UNUSED(ne30);
                //const int64_t  ne31 = src3 ? src3->ne[1] : 0;
                const int64_t  ne32 = src3 ? src3->ne[2] : 0; GGML_UNUSED(ne32);
                const int64_t  ne33 = src3 ? src3->ne[3] : 0; GGML_UNUSED(ne33);

                const uint64_t nb30 = src3 ? src3->nb[0] : 0; GGML_UNUSED(nb30);
                const uint64_t nb31 = src3 ? src3->nb[1] : 0;
                const uint64_t nb32 = src3 ? src3->nb[2] : 0; GGML_UNUSED(nb32);
                const uint64_t nb33 = src3 ? src3->nb[3] : 0; GGML_UNUSED(nb33);

                const enum ggml_type src2t = src2 ? src2->type : GGML_TYPE_COUNT; GGML_UNUSED(src2t);

                float scale;
                float max_bias;
                float softcap;

                memcpy(&scale,    ((int32_t *) dst->op_params) + 0, sizeof(scale));
                memcpy(&max_bias, ((int32_t *) dst->op_params) + 1, sizeof(max_bias));
                memcpy(&softcap,  ((int32_t *) dst->op_params) + 2, sizeof(softcap));
                if (softcap != 0.0f) {
                    scale /= softcap;
                }

                const uint32_t n_head      = src0->ne[2];
                const uint32_t n_head_log2 = 1u << (uint32_t) floorf(log2f((float) n_head));

                const float m0 = powf(2.0f, -(max_bias       ) / n_head_log2);
                const float m1 = powf(2.0f, -(max_bias / 2.0f) / n_head_log2);

                id<MTLComputePipelineState> pipeline = nil;

                bool use_vec_kernel = false;

                if (ne01 >= 4 || (ne00%128 != 0 && ne00 != 192 && ne00 != 576)) {
                    switch (src1->type) {
                        case GGML_TYPE_F16:
                            {
                                if (ne00 == 192 && ne20 == 128) {
                                    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_F16_HK192_HV128].pipeline;
                                }
                                else if (ne00 == 576 && ne20 == 512) {
                                    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_F16_HK576_HV512].pipeline;
                                } else {
                                    switch (ne00) {
                                        case 64:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_F16_H64 ].pipeline; break;
                                        case 80:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_F16_H80 ].pipeline; break;
                                        case 96:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_F16_H96 ].pipeline; break;
                                        case 112: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_F16_H112].pipeline; break;
                                        case 128: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_F16_H128].pipeline; break;
                                        case 256: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_F16_H256].pipeline; break;
                                        default:
                                            {
                                                GGML_METAL_LOG_ERROR("unsupported size: %d\n", (int)ne00);
                                                GGML_METAL_LOG_ERROR("add template specialization for this size\n");
                                                GGML_ABORT("add template specialization for this size");
                                            }
                                    }
                                }
                            } break;
                        case GGML_TYPE_Q8_0:
                            {
                                if (ne00 == 192 && ne20 == 128) {
                                    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_Q8_0_HK192_HV128].pipeline;
                                }
                                else if (ne00 == 576 && ne20 == 512) {
                                    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_Q8_0_HK576_HV512].pipeline;
                                } else {
                                    switch (ne00) {
                                        case 64:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_Q8_0_H64 ].pipeline; break;
                                        case 80:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_Q8_0_H80 ].pipeline; break;
                                        case 96:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_Q8_0_H96 ].pipeline; break;
                                        case 112: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_Q8_0_H112].pipeline; break;
                                        case 128: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_Q8_0_H128].pipeline; break;
                                        case 256: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_Q8_0_H256].pipeline; break;
                                        default:
                                            {
                                                GGML_METAL_LOG_ERROR("unsupported size: %d\n", (int)ne00);
                                                GGML_METAL_LOG_ERROR("add template specialization for this size\n");
                                                GGML_ABORT("add template specialization for this size");
                                            }
                                    }
                                }
                            } break;
                        default:
                            {
                                GGML_METAL_LOG_ERROR("unsupported type: %s\n", ggml_type_name(src1->type));
                                GGML_METAL_LOG_ERROR("add template specialization for this type\n");
                                GGML_ABORT("add template specialization for this type");
                            }
                    }
                } else {
                    use_vec_kernel = true;
                    switch (src1->type) {
                        case GGML_TYPE_F16:
                            {
                                if (ne00 == 192 && ne20 == 128) {
                                    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_F16_HK192_HV128].pipeline;
                                }
                                else if (ne00 == 576 && ne20 == 512) {
                                    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_F16_HK576_HV512].pipeline;
                                } else {
                                    switch (ne00) {
                                        case 64:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_F16_H64 ].pipeline; break;
                                        case 80:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_F16_H80 ].pipeline; break;
                                        case 96:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_F16_H96 ].pipeline; break;
                                        case 112: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_F16_H112].pipeline; break;
                                        case 128: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_F16_H128].pipeline; break;
                                        case 256: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_F16_H256].pipeline; break;
                                        default:
                                            {
                                                GGML_METAL_LOG_ERROR("unsupported size: %d\n", (int)ne00);
                                                GGML_METAL_LOG_ERROR("add template specialization for this size\n");
                                                GGML_ABORT("add template specialization for this size");
                                            }
                                    }
                                }
                            } break;
                        case GGML_TYPE_Q8_0:
                            {
                                if (ne00 == 192 && ne20 == 128) {
                                    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_Q8_0_HK192_HV128].pipeline;
                                }
                                else if (ne00 == 576 && ne20 == 512) {
                                    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_Q8_0_HK576_HV512].pipeline;
                                } else {
                                    switch (ne00) {
                                        case 64:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_Q8_0_H64 ].pipeline; break;
                                        case 80:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_Q8_0_H80 ].pipeline; break;
                                        case 96:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_Q8_0_H96 ].pipeline; break;
                                        case 112: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_Q8_0_H112].pipeline; break;
                                        case 128: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_Q8_0_H128].pipeline; break;
                                        case 256: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_FLASH_ATTN_EXT_VEC_Q8_0_H256].pipeline; break;
                                        default:
                                            {
                                                GGML_METAL_LOG_ERROR("unsupported size: %d\n", (int)ne00);
                                                GGML_METAL_LOG_ERROR("add template specialization for this size\n");
                                                GGML_ABORT("add template specialization for this size");
                                            }
                                    }
                                }
                            } break;
                        default:
                            {
                                GGML_METAL_LOG_ERROR("unsupported type: %s\n", ggml_type_name(src1->type));
                                GGML_METAL_LOG_ERROR("add template specialization for this type\n");
                                GGML_ABORT("add template specialization for this type");
                            }
                    }

                }

                typedef struct {
                    int32_t  ne01;
                    int32_t  ne02;
                    int32_t  ne03;
                    uint64_t nb01;
                    uint64_t nb02;
                    uint64_t nb03;
                    int32_t  ne11;
                    int32_t  ne_12_2; // assume K and V are same shape
                    int32_t  ne_12_3;
                    uint64_t nb11;
                    uint64_t nb12;
                    uint64_t nb13;
                    uint64_t nb21;
                    uint64_t nb22;
                    uint64_t nb23;
                    uint64_t nb31;
                    int32_t  ne1;
                    int32_t  ne2;
                    float    scale;
                    float    max_bias;
                    float    m0;
                    float    m1;
                    uint16_t n_head_log2;
                    float    logit_softcap;
                } ggml_metal_kargs_flash_attn_ext;

                ggml_metal_kargs_flash_attn_ext args = {
                    /*.ne01          =*/ ne01,
                    /*.ne02          =*/ ne02,
                    /*.ne03          =*/ ne03,
                    /*.nb01          =*/ nb01,
                    /*.nb02          =*/ nb02,
                    /*.nb03          =*/ nb03,
                    /*.ne11          =*/ ne11,
                    /*.ne_12_2       =*/ ne12,
                    /*.ne_12_3       =*/ ne13,
                    /*.nb11          =*/ nb11,
                    /*.nb12          =*/ nb12,
                    /*.nb13          =*/ nb13,
                    /*.nb21          =*/ nb21,
                    /*.nb22          =*/ nb22,
                    /*.nb23          =*/ nb23,
                    /*.nb31          =*/ nb31,
                    /*.ne1           =*/ ne1,
                    /*.ne2           =*/ ne2,
                    /*.scale         =*/ scale,
                    /*.max_bias      =*/ max_bias,
                    /*.m0            =*/ m0,
                    /*.m1            =*/ m1,
                    /*.n_head_log2   =*/ n_head_log2,
                    /*.logit_softcap =*/ softcap,
                };

                [encoder setComputePipelineState:pipeline];
                [encoder setBytes:&args length:sizeof(args)     atIndex:0];
                [encoder setBuffer:id_src0 offset:offs_src0     atIndex:1];
                [encoder setBuffer:id_src1 offset:offs_src1     atIndex:2];
                [encoder setBuffer:id_src2 offset:offs_src2     atIndex:3];
                if (id_src3) {
                    [encoder setBuffer:id_src3 offset:offs_src3 atIndex:4];
                } else {
                    [encoder setBuffer:id_src0 offset:offs_src0 atIndex:4];
                }
                [encoder setBuffer:id_dst offset:offs_dst       atIndex:5];

                if (!use_vec_kernel) {
                    // half8x8 kernel
                    const int64_t nqptg = 8;  // queries per threadgroup    !! sync with kernel template arguments !!
                    const int64_t ncpsg = 32; // cache values per simdgroup !! sync with kernel template arguments !!

                    GGML_ASSERT(nqptg <= 32);
                    GGML_ASSERT(nqptg  % 8  == 0);
                    GGML_ASSERT(ncpsg  % 32 == 0);

                    // 2*(2*ncpsg + nqptg)*(nsg)
                    // ncpsg soft_max values + ncpsg mask values + a diagonal scaling matrix (in float)
                    //
                    // 16*32*(nsg)
                    // the shared memory needed for the simdgroups to load the KV cache
                    // each thread loads (dequantizes) 16 head elements, there are 32 threads in th SG
                    //
#define FATTN_SMEM(nsg) (GGML_PAD((nqptg*(ne00 + 2*(2*ncpsg + nqptg)*(nsg)) + 16*32*(nsg))*(sizeof(float)/2), 16))

                    int64_t nsgmax = 2;

                    while (true) {
                        const size_t smem = FATTN_SMEM(nsgmax);
                        if (smem > ctx->device.maxThreadgroupMemoryLength) {
                            break;
                        }
                        nsgmax *= 2;
                    }
                    nsgmax /= 2;

                    // simdgroups per threadgroup (a.k.a. warps)
                    const int64_t nsg = ne01 <= nqptg ? MAX(4, MIN(nsgmax, MIN(ne11/ncpsg, (int64_t) pipeline.maxTotalThreadsPerThreadgroup/32))) : 4;

                    const size_t smem = FATTN_SMEM(nsg);

                    //printf("smem: %zu, max: %zu, nsg = %d\n", smem, device.maxThreadgroupMemoryLength, (int) nsg);
                    GGML_ASSERT(smem <= ctx->device.maxThreadgroupMemoryLength);
                    [encoder setThreadgroupMemoryLength:smem atIndex:0];
#undef FATTN_SMEM
                    [encoder dispatchThreadgroups:MTLSizeMake((ne01 + nqptg - 1)/nqptg, ne02, ne03) threadsPerThreadgroup:MTLSizeMake(32, nsg, 1)];

                } else {
                    // half1x4 kernel
                    const int64_t nqptg = 1;  // queries per threadgroup    !! sync with kernel template arguments !!
                    const int64_t ncpsg = 32; // cache values per simdgroup !! sync with kernel template arguments !!

                    GGML_ASSERT(nqptg <= 32);
                    GGML_ASSERT(nqptg  % 1  == 0);
                    GGML_ASSERT(ncpsg  % 32 == 0);

                    // ne00 + 2*ncpsg*(nsg)
                    // for each query, we load it as f16 in shared memory (ne00)
                    // and store the soft_max values and the mask
                    //
                    // ne00*(nsg)
                    // each simdgroup has a full f16 head vector in shared mem to accumulate results
                    //
#define FATTN_SMEM(nsg) (GGML_PAD((nqptg*(GGML_PAD(ne00, 128) + 4*ncpsg*(nsg)) + ne20*(nsg))*(sizeof(float)/2), 16))

                    int64_t nsgmax = 2;
                    while (true) {
                        const size_t smem = FATTN_SMEM(nsgmax);
                        if (smem > ctx->device.maxThreadgroupMemoryLength) {
                            break;
                        }
                        nsgmax *= 2;
                    }
                    nsgmax /= 2;

                    // simdgroups per threadgroup (a.k.a. warps)
                    const int64_t nsgt = MAX(2, MIN(nsgmax, MIN(ne11/ncpsg, (int64_t) pipeline.maxTotalThreadsPerThreadgroup/32)));

                    int64_t nsg = 1;
                    while (nsg <= nsgt) {
                        nsg *= 2;
                    }
                    nsg /= 2;

                    const size_t smem = FATTN_SMEM(nsg);

                    //printf("smem: %zu, max: %zu, nsg = %d\n", smem, device.maxThreadgroupMemoryLength, (int) nsg);
                    GGML_ASSERT(smem <= ctx->device.maxThreadgroupMemoryLength);
                    [encoder setThreadgroupMemoryLength:smem atIndex:0];
#undef FATTN_SMEM
                    [encoder dispatchThreadgroups:MTLSizeMake((ne01 + nqptg - 1)/nqptg, ne02, ne03) threadsPerThreadgroup:MTLSizeMake(32, nsg, 1)];

                }
            } break;
        case GGML_OP_DUP:
        case GGML_OP_CPY:
       case GGML_OP_CONT:
            {
                GGML_ASSERT(ne00 % ggml_blck_size(src0->type) == 0);

                int nth = MIN(1024, ne00/ggml_blck_size(src0->type));

                id<MTLComputePipelineState> pipeline = nil;

                switch (src0t) {
                    case GGML_TYPE_F32:
                        {
                            GGML_ASSERT(ne0 % ggml_blck_size(dst->type) == 0);

                            switch (dstt) {
                                case GGML_TYPE_F32:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_CPY_F32_F32].pipeline; break;
                                case GGML_TYPE_F16:    pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_CPY_F32_F16].pipeline; break;
                                case GGML_TYPE_Q8_0:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_CPY_F32_Q8_0].pipeline; break;
                                case GGML_TYPE_Q4_0:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_CPY_F32_Q4_0].pipeline; break;
                                case GGML_TYPE_Q4_1:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_CPY_F32_Q4_1].pipeline; break;
                                case GGML_TYPE_Q5_0:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_CPY_F32_Q5_0].pipeline; break;
                                case GGML_TYPE_Q5_1:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_CPY_F32_Q5_1].pipeline; break;
                                case GGML_TYPE_Q6_0:   pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_CPY_F32_Q6_0].pipeline; break;
                                case GGML_TYPE_IQ4_NL: pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_CPY_F32_IQ4_NL].pipeline; break;
                                default: GGML_ABORT("not implemented");
                            };
                        } break;
                    case GGML_TYPE_F16:
                        {
                            switch (dstt) {
                                case GGML_TYPE_F32:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_CPY_F16_F32].pipeline; break;
                                case GGML_TYPE_F16:  pipeline = ctx->kernels[GGML_METAL_KERNEL_TYPE_CPY_F16_F16].pipeline; break;
                                default: GGML_ABORT("not implemented");
                            };
                        } break;
                    default: GGML_ABORT("not implemented");
                }

                [encoder setComputePipelineState:pipeline];
                [encoder setBuffer:id_src0 offset:offs_src0        atIndex:0];
                [encoder setBuffer:id_dst  offset:offs_dst         atIndex:1];
                [encoder setBytes:&ne00    length:sizeof( int64_t) atIndex:2];
                [encoder setBytes:&ne01    length:sizeof( int64_t) atIndex:3];
                [encoder setBytes:&ne02    length:sizeof( int64_t) atIndex:4];
                [encoder setBytes:&ne03    length:sizeof( int64_t) atIndex:5];
                [encoder setBytes:&nb00    length:sizeof(uint64_t) atIndex:6];
                [encoder setBytes:&nb01    length:sizeof(uint64_t) atIndex:7];
                [encoder setBytes:&nb02    length:sizeof(uint64_t) atIndex:8];
                [encoder setBytes:&nb03    length:sizeof(uint64_t) atIndex:9];
                [encoder setBytes:&ne0     length:sizeof( int64_t) atIndex:10];
                [encoder setBytes:&ne1     length:sizeof( int64_t) atIndex:11];
                [encoder setBytes:&ne2     length:sizeof( int64_t) atIndex:12];
                [encoder setBytes:&ne3     length:sizeof( int64_t) atIndex:13];
                [encoder setBytes:&nb0     length:sizeof(uint64_t) atIndex:14];
                [encoder setBytes:&nb1     length:sizeof(uint64_t) atIndex:15];
                [encoder setBytes:&nb2     length:sizeof(uint64_t) atIndex:16];
                [encoder setBytes:&nb3     length:sizeof(uint64_t) atIndex:17];

                [encoder dispatchThreadgroups:MTLSizeMake(ne01, ne02, ne03) threadsPerThreadgroup:MTLSizeMake(nth, 1, 1)];
            } break;
       default:
            {
                GGML_METAL_LOG_ERROR("%s: error: node %s, op = %8s not implemented\n", __func__, dst->name, ggml_op_name(dst->op));
                GGML_ABORT("fatal error");
            }
    }

}

static enum ggml_status ggml_metal_graph_compute(
        struct ggml_backend_metal_context * ctx,
               struct ggml_cgraph * gf) {

    // number of nodes encoded by the main thread (empirically determined)
    const int n_main = 128;

    // number of threads in addition to the main thread
    const int n_cb = ctx->n_cb;

    @autoreleasepool {
        ctx->gf = gf;

        ctx->n_nodes_0 = MIN(n_main, gf->n_nodes);
        ctx->n_nodes_1 = gf->n_nodes - ctx->n_nodes_0;

        ctx->n_nodes_per_cb = (ctx->n_nodes_1 + ctx->n_cb - 1) / ctx->n_cb;

        const bool should_capture = ctx->capture_next_compute;
        if (should_capture) {
            ctx->capture_next_compute = false;

            if (!ctx->capture_started) {
                // create capture scope
                ctx->capture_scope = [[MTLCaptureManager sharedCaptureManager] newCaptureScopeWithDevice:ctx->device]; //ctx_dev->mtl_device];

                MTLCaptureDescriptor * descriptor = [MTLCaptureDescriptor new];
                descriptor.captureObject = ctx->capture_scope;
                descriptor.destination = MTLCaptureDestinationGPUTraceDocument;
                descriptor.outputURL = [NSURL fileURLWithPath:[NSString stringWithFormat:@"/tmp/perf-metal.gputrace"]];

                NSError * error = nil;
                if (![[MTLCaptureManager sharedCaptureManager] startCaptureWithDescriptor:descriptor error:&error]) {
                    printf("%s: error: unable to start capture '%s'\n", __func__, [[error localizedDescription] UTF8String]);
                } else {
                    [ctx->capture_scope beginScope];
                    ctx->capture_started = true;
                }
            }
        }

        // the main thread commits the first few commands immediately
        // command_buffer[n_cb]
        {
            id<MTLCommandBuffer> command_buffer = [ctx->queue commandBufferWithUnretainedReferences];
            ctx->command_buffers[n_cb] = command_buffer;

            [command_buffer enqueue];
            ctx->encode_async(n_cb);
        }

        // prepare the rest of the command buffers asynchronously
        // command_buffer[0.. n_cb)
        for (int cb_idx = 0; cb_idx < n_cb; ++cb_idx) {
            id<MTLCommandBuffer> command_buffer = [ctx->queue commandBufferWithUnretainedReferences];
            ctx->command_buffers[cb_idx] = command_buffer;

            // always enqueue the first two command buffers
            // enqueue all of the command buffers if we don't need to abort
            if (cb_idx < 2 || ctx->abort_callback == NULL) {
                [command_buffer enqueue];
            }
        }

        dispatch_apply(n_cb, ctx->d_queue, ctx->encode_async);

        // wait for completion and check status of each command buffer
        // needed to detect if the device ran out-of-memory for example (#1881)
        {
            id<MTLCommandBuffer> command_buffer = ctx->command_buffers[n_cb];
            [command_buffer waitUntilCompleted];

            MTLCommandBufferStatus status = [command_buffer status];
            if (status != MTLCommandBufferStatusCompleted) {
                printf("%s: command buffer %d failed with status %lu\n", __func__, n_cb, status);
                if (status == MTLCommandBufferStatusError) {
                    printf("error: %s\n", [[command_buffer error].localizedDescription UTF8String]);
                }

                return GGML_STATUS_FAILED;
            }
        }
        for (int i = 0; i < n_cb; ++i) {
            id<MTLCommandBuffer> command_buffer = ctx->command_buffers[i];
            [command_buffer waitUntilCompleted];

            MTLCommandBufferStatus status = [command_buffer status];
            if (status != MTLCommandBufferStatusCompleted) {
                printf("%s: command buffer %d failed with status %lu\n", __func__, i, status);
                if (status == MTLCommandBufferStatusError) {
                    printf("error: %s\n", [[command_buffer error].localizedDescription UTF8String]);
                }

                return GGML_STATUS_FAILED;
            }

            id<MTLCommandBuffer> next_buffer = (i + 1 < n_cb ? ctx->command_buffers[i + 1] : nil);
            if (!next_buffer) {
                continue;
            }

            const bool next_queued = ([next_buffer status] != MTLCommandBufferStatusNotEnqueued);
            if (next_queued) {
                continue;
            }

            if (ctx->abort_callback && ctx->abort_callback(ctx->abort_callback_data)) {
                printf("%s: command buffer %d aborted", __func__, i);
                return GGML_STATUS_ABORTED;
            }

            [next_buffer commit];
        }

        if (!should_capture && ctx->capture_started) {
            [ctx->capture_scope endScope];
            [[MTLCaptureManager sharedCaptureManager] stopCapture];
        }
    }

    return GGML_STATUS_SUCCESS;
}

////////////////////////////////////////////////////////////////////////////////

// backend interface

// default buffer
static id<MTLDevice> g_backend_device = nil;
static int g_backend_device_ref_count = 0;

static id<MTLDevice> ggml_backend_metal_get_device(void) {
    if (g_backend_device == nil) {
        g_backend_device = MTLCreateSystemDefaultDevice();
    }

    g_backend_device_ref_count++;

    return g_backend_device;
}

static void ggml_backend_metal_free_device(void) {
    assert(g_backend_device_ref_count > 0);

    g_backend_device_ref_count--;

    if (g_backend_device_ref_count == 0) {
        [g_backend_device release];
        g_backend_device = nil;
    }
}

GGML_CALL static const char * ggml_backend_metal_buffer_get_name(ggml_backend_buffer_t buffer) {
    return "Metal";

    UNUSED(buffer);
}

GGML_CALL static void ggml_backend_metal_buffer_free_buffer(ggml_backend_buffer_t buffer) {
    struct ggml_backend_metal_buffer_context * ctx = (struct ggml_backend_metal_buffer_context *)buffer->context;

    for (int i = 0; i < ctx->n_buffers; i++) {
        [ctx->buffers[i].metal release];
    }
    ggml_backend_metal_free_device();

    if (ctx->owned) {
#if TARGET_OS_OSX
        vm_deallocate((vm_map_t)mach_task_self(), (vm_address_t)ctx->all_data, ctx->all_size);
#else
        free(ctx->all_data);
#endif
    }

    free(ctx);
}

GGML_CALL static void * ggml_backend_metal_buffer_get_base(ggml_backend_buffer_t buffer) {
    struct ggml_backend_metal_buffer_context * ctx = (struct ggml_backend_metal_buffer_context *)buffer->context;

    return ctx->all_data;
}

GGML_CALL  void ggml_backend_metal_buffer_memset_tensor(ggml_backend_buffer_t buffer, struct ggml_tensor * tensor, uint8_t value, size_t offset, size_t size) {
    memset((char *)tensor->data + offset, value, size);

    GGML_UNUSED(buffer);
}

GGML_CALL static void ggml_backend_metal_buffer_set_tensor(ggml_backend_buffer_t buffer, struct ggml_tensor * tensor, const void * data, size_t offset, size_t size) {
    memcpy((char *)tensor->data + offset, data, size);

    UNUSED(buffer);
}

GGML_CALL static void ggml_backend_metal_buffer_get_tensor(ggml_backend_buffer_t buffer, const struct ggml_tensor * tensor, void * data, size_t offset, size_t size) {
    memcpy(data, (const char *)tensor->data + offset, size);

    UNUSED(buffer);
}

GGML_CALL static bool ggml_backend_metal_buffer_cpy_tensor(ggml_backend_buffer_t buffer, const struct ggml_tensor * src, struct ggml_tensor * dst) {
    if (ggml_backend_buffer_is_host(src->buffer)) {
        memcpy(dst->data, src->data, ggml_nbytes(src));
        return true;
    }
    return false;

    UNUSED(buffer);
}

GGML_CALL static void ggml_backend_metal_buffer_clear(ggml_backend_buffer_t buffer, uint8_t value) {
    struct ggml_backend_metal_buffer_context * ctx = (struct ggml_backend_metal_buffer_context *)buffer->context;

    memset(ctx->all_data, value, ctx->all_size);
}

static struct ggml_backend_buffer_i ggml_backend_metal_buffer_i = {
    /* .get_name        = */ ggml_backend_metal_buffer_get_name,
    /* .free_buffer     = */ ggml_backend_metal_buffer_free_buffer,
    /* .get_base        = */ ggml_backend_metal_buffer_get_base,
    /* .init_tensor     = */ NULL,
    /* .memset_tensor   = */ ggml_backend_metal_buffer_memset_tensor,
    /* .set_tensor      = */ ggml_backend_metal_buffer_set_tensor,
    /* .get_tensor      = */ ggml_backend_metal_buffer_get_tensor,
    /* .cpy_tensor      = */ ggml_backend_metal_buffer_cpy_tensor,
    /* .clear           = */ ggml_backend_metal_buffer_clear,
    /* .reset           = */ NULL,
};

// default buffer type

GGML_CALL static const char * ggml_backend_metal_buffer_type_get_name(ggml_backend_buffer_type_t buft) {
    return "Metal";

    UNUSED(buft);
}

static void ggml_backend_metal_log_allocated_size(id<MTLDevice> device, size_t size_aligned) {
#ifndef GGML_METAL_NDEBUG
#if TARGET_OS_OSX || (TARGET_OS_IOS && __clang_major__ >= 15)
    if (@available(macOS 10.12, iOS 16.0, *)) {
        GGML_METAL_LOG_INFO("%s: allocated buffer, size = %8.2f MiB, (%8.2f / %8.2f)",
                __func__,
                size_aligned / 1024.0 / 1024.0,
                device.currentAllocatedSize / 1024.0 / 1024.0,
                device.recommendedMaxWorkingSetSize / 1024.0 / 1024.0);

        if (device.currentAllocatedSize > device.recommendedMaxWorkingSetSize) {
            GGML_METAL_LOG_WARN("%s: warning: current allocated size is greater than the recommended max working set size\n", __func__);
        } else {
            GGML_METAL_LOG_INFO("\n");
        }
    } else {
        GGML_METAL_LOG_INFO("%s: allocated buffer, size = %8.2f MiB, (%8.2f)\n",
                __func__,
                size_aligned / 1024.0 / 1024.0,
                device.currentAllocatedSize / 1024.0 / 1024.0);
    }
#endif
#endif
    UNUSED(device);
    UNUSED(size_aligned);
}

GGML_CALL static ggml_backend_buffer_t ggml_backend_metal_buffer_type_alloc_buffer(ggml_backend_buffer_type_t buft, size_t size) {
    struct ggml_backend_metal_buffer_context * ctx = malloc(sizeof(struct ggml_backend_metal_buffer_context));

    const size_t size_page = sysconf(_SC_PAGESIZE);

    size_t size_aligned = size;
    if ((size_aligned % size_page) != 0) {
        size_aligned += (size_page - (size_aligned % size_page));
    }

    id<MTLDevice> device = ggml_backend_metal_get_device();

    ctx->all_data = ggml_metal_host_malloc(size_aligned);
    ctx->all_size = size_aligned;
    ctx->owned = true;
    ctx->n_buffers = 1;

    if (ctx->all_data != NULL) {
        ctx->buffers[0].data = ctx->all_data;
        ctx->buffers[0].size = size;
        ctx->buffers[0].metal = [device newBufferWithBytesNoCopy:ctx->all_data
                        length:size_aligned
                        options:MTLResourceStorageModeShared
                        deallocator:nil];
    }

    if (ctx->all_data == NULL || ctx->buffers[0].metal == nil) {
        GGML_METAL_LOG_ERROR("%s: error: failed to allocate buffer, size = %8.2f MiB\n", __func__, size_aligned / 1024.0 / 1024.0);
        free(ctx);
        ggml_backend_metal_free_device();
        return NULL;
    }

    //ggml_backend_metal_log_allocated_size(device, size_aligned);

    return ggml_backend_buffer_init(buft, ggml_backend_metal_buffer_i, ctx, size);
}

GGML_CALL static size_t ggml_backend_metal_buffer_type_get_alignment(ggml_backend_buffer_type_t buft) {
    return 32;
    UNUSED(buft);
}

GGML_CALL static size_t ggml_backend_metal_buffer_type_get_max_size(ggml_backend_buffer_type_t buft) {
    id<MTLDevice> device = ggml_backend_metal_get_device();
    size_t max_size = device.maxBufferLength;
    ggml_backend_metal_free_device();

    return max_size;

    UNUSED(buft);
}

GGML_CALL static bool ggml_backend_metal_buffer_type_is_host(ggml_backend_buffer_type_t buft) {
    return true;

    UNUSED(buft);
}

GGML_CALL ggml_backend_buffer_type_t ggml_backend_metal_buffer_type(void) {
    static struct ggml_backend_buffer_type ggml_backend_buffer_type_metal = {
        /* .iface = */ {
            /* .get_name         = */ ggml_backend_metal_buffer_type_get_name,
            /* .alloc_buffer     = */ ggml_backend_metal_buffer_type_alloc_buffer,
            /* .get_alignment    = */ ggml_backend_metal_buffer_type_get_alignment,
            /* .get_max_size     = */ ggml_backend_metal_buffer_type_get_max_size,
            /* .get_alloc_size   = */ NULL, // defaults to ggml_nbytes
            /* .is_host          = */ ggml_backend_metal_buffer_type_is_host,
        },
        /* .context = */ NULL,
    };

    return &ggml_backend_buffer_type_metal;
}

// buffer from ptr

GGML_CALL ggml_backend_buffer_t ggml_backend_metal_buffer_from_ptr(void * data, size_t size, size_t max_size) {
    struct ggml_backend_metal_buffer_context * ctx = malloc(sizeof(struct ggml_backend_metal_buffer_context));

    ctx->all_data = data;
    ctx->all_size = size;
    ctx->owned = false;
    ctx->n_buffers = 0;

    const size_t size_page = sysconf(_SC_PAGESIZE);

    // page-align the data ptr
    {
        const uintptr_t offs = (uintptr_t) data % size_page;
        data  = (void *) ((char *) data - offs);
        size += offs;
    }

    size_t size_aligned = size;
    if ((size_aligned % size_page) != 0) {
        size_aligned += (size_page - (size_aligned % size_page));
    }

    id<MTLDevice> device = ggml_backend_metal_get_device();

    // the buffer fits into the max buffer size allowed by the device
    if (size_aligned <= device.maxBufferLength) {
        ctx->buffers[ctx->n_buffers].data = data;
        ctx->buffers[ctx->n_buffers].size = size;

        ctx->buffers[ctx->n_buffers].metal = [device newBufferWithBytesNoCopy:data length:size_aligned options:MTLResourceStorageModeShared deallocator:nil];

        if (ctx->buffers[ctx->n_buffers].metal == nil) {
            GGML_METAL_LOG_ERROR("%s: error: failed to allocate buffer, size = %8.2f MiB\n", __func__, size_aligned / 1024.0 / 1024.0);
            return false;
        }

        ggml_backend_metal_log_allocated_size(device, size_aligned);

        ++ctx->n_buffers;
    } else {
        // this overlap between the views will guarantee that the tensor with the maximum size will fully fit into
        // one of the views
        const size_t size_ovlp = ((max_size + size_page - 1) / size_page + 1) * size_page; // round-up 2 pages just in case
        const size_t size_step = device.maxBufferLength - size_ovlp;
        const size_t size_view = device.maxBufferLength;

        for (size_t i = 0; i < size; i += size_step) {
            const size_t size_step_aligned = (i + size_view <= size) ? size_view : (size_aligned - i);

            ctx->buffers[ctx->n_buffers].data = (void *) ((uint8_t *) data + i);
            ctx->buffers[ctx->n_buffers].size = size_step_aligned;

            ctx->buffers[ctx->n_buffers].metal = [device newBufferWithBytesNoCopy:(void *) ((uint8_t *) data + i) length:size_step_aligned options:MTLResourceStorageModeShared deallocator:nil];

            if (ctx->buffers[ctx->n_buffers].metal == nil) {
                GGML_METAL_LOG_ERROR("%s: error: failed to allocate buffer, size = %8.2f MiB\n", __func__, size_step_aligned / 1024.0 / 1024.0);
                return false;
            }

            ggml_backend_metal_log_allocated_size(device, size_step_aligned);

            if (i + size_step < size) {
                GGML_METAL_LOG_INFO("\n");
            }

            ++ctx->n_buffers;
        }
    }

    return ggml_backend_buffer_init(ggml_backend_metal_buffer_type(), ggml_backend_metal_buffer_i, ctx, size);
}

// backend

GGML_CALL static const char * ggml_backend_metal_name(ggml_backend_t backend) {
    return "Metal";

    UNUSED(backend);
}

GGML_CALL static void ggml_backend_metal_free(ggml_backend_t backend) {
    struct ggml_backend_metal_context * ctx = (struct ggml_backend_metal_context *)backend->context;
    ggml_metal_free(ctx);
    free(backend);
}

GGML_CALL static ggml_backend_buffer_type_t ggml_backend_metal_get_default_buffer_type(ggml_backend_t backend) {
    return ggml_backend_metal_buffer_type();

    UNUSED(backend);
}

GGML_CALL static enum ggml_status ggml_backend_metal_graph_compute(ggml_backend_t backend, struct ggml_cgraph * cgraph) {
    struct ggml_backend_metal_context * metal_ctx = (struct ggml_backend_metal_context *)backend->context;

    return ggml_metal_graph_compute(metal_ctx, cgraph);
}

GGML_CALL static bool ggml_backend_metal_supports_op(ggml_backend_t backend, const struct ggml_tensor * op) {
    struct ggml_backend_metal_context * metal_ctx = (struct ggml_backend_metal_context *)backend->context;

    return ggml_metal_supports_op(metal_ctx, op);
}

GGML_CALL static bool ggml_backend_metal_supports_buft(ggml_backend_t backend, ggml_backend_buffer_type_t buft) {
    return buft->iface.get_name == ggml_backend_metal_buffer_type_get_name;

    UNUSED(backend);
}

static struct ggml_backend_i ggml_backend_metal_i = {
    /* .get_name                = */ ggml_backend_metal_name,
    /* .free                    = */ ggml_backend_metal_free,
    /* .get_default_buffer_type = */ ggml_backend_metal_get_default_buffer_type,
    /* .set_tensor_async        = */ NULL,
    /* .get_tensor_async        = */ NULL,
    /* .cpy_tensor_async        = */ NULL,
    /* .synchronize             = */ NULL,
    /* .graph_plan_create       = */ NULL,
    /* .graph_plan_free         = */ NULL,
    /* .graph_plan_update       = */ NULL,
    /* .graph_plan_compute      = */ NULL,
    /* .graph_compute           = */ ggml_backend_metal_graph_compute,
    /* .supports_op             = */ ggml_backend_metal_supports_op,
    /* .supports_buft           = */ ggml_backend_metal_supports_buft,
    /* .offload_op              = */ NULL,
    /* .event_new               = */ NULL,
    /* .event_free              = */ NULL,
    /* .event_record            = */ NULL,
    /* .event_wait              = */ NULL,
    /* .event_synchronize       = */ NULL,
};

void ggml_backend_metal_log_set_callback(ggml_log_callback log_callback, void * user_data) {
    ggml_metal_log_callback  = log_callback;
    ggml_metal_log_user_data = user_data;
}

static ggml_guid_t ggml_backend_metal_guid(void) {
    static ggml_guid guid = { 0x81, 0xa1, 0x8b, 0x1e, 0x71, 0xec, 0x79, 0xed, 0x2b, 0x85, 0xdc, 0x8a, 0x61, 0x98, 0x30, 0xe6 };
    return &guid;
}

ggml_backend_t ggml_backend_metal_init(void) {
    struct ggml_backend_metal_context * ctx = ggml_metal_init(GGML_DEFAULT_N_THREADS);
    if (ctx == NULL) {
        GGML_METAL_LOG_ERROR("%s: error: failed to allocate context\n", __func__);
        return NULL;
    }

    ggml_backend_t metal_backend = malloc(sizeof(struct ggml_backend));

    *metal_backend = (struct ggml_backend) {
        /* .guid      = */ ggml_backend_metal_guid(),
        /* .interface = */ ggml_backend_metal_i,
        /* .context   = */ ctx,
    };

    return metal_backend;
}

bool ggml_backend_is_metal(ggml_backend_t backend) {
    return backend != NULL && ggml_guid_matches(backend->guid, ggml_backend_metal_guid());
}

void ggml_backend_metal_set_n_cb(ggml_backend_t backend, int n_cb) {
    GGML_ASSERT(ggml_backend_is_metal(backend));

    struct ggml_backend_metal_context * ctx = (struct ggml_backend_metal_context *)backend->context;
    if (ctx->n_cb != n_cb) {
        ctx->n_cb = MIN(n_cb, GGML_METAL_MAX_COMMAND_BUFFERS);

        if (ctx->n_cb > 2) {
            GGML_METAL_LOG_WARN("%s: n_cb = %d, using n_cb > 2 is not recommended and can degrade the performance in some cases\n", __func__, n_cb);
        }
    }

    if (ctx->encode_async) {
        Block_release(ctx->encode_async);
    }

    ctx->encode_async = Block_copy(^(size_t iter) {
        const int cb_idx = iter;
        const int n_cb_l = ctx->n_cb;

        const int n_nodes_0 = ctx->n_nodes_0;
        const int n_nodes_1 = ctx->n_nodes_1;

        const int n_nodes_per_cb = ctx->n_nodes_per_cb;

        id<MTLCommandBuffer> command_buffer  = ctx->command_buffers[cb_idx];
        id<MTLComputeCommandEncoder> encoder = [command_buffer computeCommandEncoder];

        int node_start = 0;
        int node_end   = n_nodes_0;

        if (cb_idx < n_cb_l) {
            node_start = n_nodes_0 + (                                         (cb_idx + 0) * n_nodes_per_cb);
            node_end   = n_nodes_0 + (MIN((cb_idx == n_cb_l - 1) ? n_nodes_1 : (cb_idx + 1) * n_nodes_per_cb, n_nodes_1));
        }

        const bool should_capture = ctx->capture_next_compute;

        for (int idx = node_start; idx < node_end; ++idx) {
            struct ggml_tensor * node = ctx->gf->nodes[idx];
            if (should_capture) {
                [encoder pushDebugGroup:[NSString stringWithCString:ggml_op_desc(node) encoding:NSUTF8StringEncoding]];
            }

            ggml_metal_encode_node(ctx, node, encoder);

            if (should_capture) {
                [encoder popDebugGroup];
            }
        }

        [encoder endEncoding];

        if (cb_idx < 2 || ctx->abort_callback == NULL) {
            [command_buffer commit];
        }
    });

}

void ggml_backend_metal_set_abort_callback(ggml_backend_t backend, ggml_abort_callback abort_callback, void * user_data) {
    GGML_ASSERT(ggml_backend_is_metal(backend));

    struct ggml_backend_metal_context * ctx = (struct ggml_backend_metal_context *)backend->context;

    ctx->abort_callback = abort_callback;
    ctx->abort_callback_data = user_data;
}

bool ggml_backend_metal_supports_family(ggml_backend_t backend, int family) {
    GGML_ASSERT(ggml_backend_is_metal(backend));

    struct ggml_backend_metal_context * ctx = (struct ggml_backend_metal_context *)backend->context;

    return [ctx->device supportsFamily:(MTLGPUFamilyApple1 + family - 1)];
}

void ggml_backend_metal_capture_next_compute(ggml_backend_t backend) {
    GGML_ASSERT(ggml_backend_is_metal(backend));

    struct ggml_backend_metal_context * ctx = (struct ggml_backend_metal_context *)backend->context;
    ctx->should_capture_next_compute = true;
}

GGML_CALL ggml_backend_t ggml_backend_reg_metal_init(const char * params, void * user_data); // silence warning

GGML_CALL ggml_backend_t ggml_backend_reg_metal_init(const char * params, void * user_data) {
    return ggml_backend_metal_init();

    GGML_UNUSED(params);
    GGML_UNUSED(user_data);
}
