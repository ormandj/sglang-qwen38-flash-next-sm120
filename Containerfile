# Qwen3.8-Flash-Next FP8 on SGLang for RTX PRO 6000 Blackwell (SM120).
ARG QWEN38_RELEASE_VERSION=0.1.0
ARG QWEN38_RELEASE_CANDIDATE=9
ARG QWEN38_CACHE_SCHEMA=v8
ARG QWEN38_SGLANG_BASE=lmsysorg/sglang:nightly-dev-cu13-20260826-41e7612d@sha256:5f9319ef797bd258594de8f879911ffd8300f3393e1b885fedea4a9bea74294d
ARG QWEN38_SGLANG_BASE_HEAD=41e7612dee44e262ba2f474546a5144c449c6596
ARG QWEN38_SGLANG_MAIN_HEAD=7f27bf470824f452a34e866d22ab5e332a23e26f
ARG QWEN38_SGLANG_MAIN_TREE=9a15203d2cc3b256f78a96a6617ee5c783e1b1c1
ARG QWEN38_SGLANG_PR36497_HEAD=73a255206f916366c8d26d4022f82ddfb0ab558d
ARG QWEN38_SGLANG_PR36556_HEAD=dac5523d1e5d2f4297fec40ef02fc76fb0f662d1
ARG QWEN38_SGLANG_INTEGRATION_HEAD=b03fdaa5c4bb011908e9359c498dbe20a5e05deb
ARG QWEN38_SGLANG_EFFECTIVE_TREE=2bf157ed74501598305c55f478025ea1f4d80ec8
ARG QWEN38_MODEL_REVISION=bcd9f01ddc9cff2316eb84281bebcd5b058bddce
ARG QWEN38_FLASHINFER_VERSION=0.6.18
ARG QWEN38_FLASHINFER_MAIN_HEAD=e4b7fa4b7c3ba5e17286d9c59f2bcf2ca07e0a6d
ARG QWEN38_FLASHINFER_MAIN_TREE=2c9c021eb87fb09c982076b8a0b63514bc399e56
ARG IMAGE_SOURCE
ARG IMAGE_SOURCE_REVISION

FROM ${QWEN38_SGLANG_BASE} AS runtime
ARG QWEN38_RELEASE_VERSION
ARG QWEN38_RELEASE_CANDIDATE
ARG QWEN38_CACHE_SCHEMA
ARG QWEN38_SGLANG_BASE_HEAD
ARG QWEN38_SGLANG_MAIN_HEAD
ARG QWEN38_SGLANG_MAIN_TREE
ARG QWEN38_SGLANG_PR36497_HEAD
ARG QWEN38_SGLANG_PR36556_HEAD
ARG QWEN38_SGLANG_INTEGRATION_HEAD
ARG QWEN38_SGLANG_EFFECTIVE_TREE
ARG QWEN38_MODEL_REVISION
ARG QWEN38_FLASHINFER_VERSION
ARG QWEN38_FLASHINFER_MAIN_HEAD
ARG QWEN38_FLASHINFER_MAIN_TREE
ARG IMAGE_SOURCE
ARG IMAGE_SOURCE_REVISION

ENV PYTHONPATH=/sgl-workspace/sglang/python

RUN set -e; \
    git init -q /tmp/flashinfer-main; \
    cd /tmp/flashinfer-main; \
    git remote add origin https://github.com/flashinfer-ai/flashinfer.git; \
    git fetch --depth=1 origin "${QWEN38_FLASHINFER_MAIN_HEAD}"; \
    git checkout --detach FETCH_HEAD; \
    test "$(git rev-parse HEAD)" = "${QWEN38_FLASHINFER_MAIN_HEAD}"; \
    test "$(git rev-parse HEAD^{tree})" = "${QWEN38_FLASHINFER_MAIN_TREE}"; \
    git submodule update --init --recursive --depth=1; \
    uv pip uninstall --python /opt/sglang/bin/python \
      flashinfer-cubin flashinfer-jit-cache; \
    BUILD_NVEP=0 FLASHINFER_CUDA_ARCH_LIST=12.0f \
      uv pip install --python /opt/sglang/bin/python --reinstall --no-deps .; \
    FLASHINFER_CUBIN_DIR=/tmp/flashinfer-main/flashinfer-cubin/flashinfer_cubin/cubins \
      uv pip install --python /opt/sglang/bin/python --reinstall --no-deps \
      --no-build-isolation ./flashinfer-cubin; \
    cd /; \
    rm -rf /tmp/flashinfer-main

COPY patches/sglang/0001-qwen38-flash-next-v0.1.0-rc.9.patch /tmp/sglang-release.patch
RUN set -e; cd /sgl-workspace/sglang; \
    git config --local --unset-all http.https://github.com/.extraheader || true; \
    git remote set-url origin https://github.com/sgl-project/sglang.git; \
    git fetch --depth=1 origin "${QWEN38_SGLANG_MAIN_HEAD}"; \
    git checkout --detach FETCH_HEAD; \
    git reset --hard "${QWEN38_SGLANG_MAIN_HEAD}"; \
    test "$(git rev-parse HEAD)" = "${QWEN38_SGLANG_MAIN_HEAD}"; \
    test "$(git rev-parse HEAD^{tree})" = "${QWEN38_SGLANG_MAIN_TREE}"; \
    git apply --index --binary /tmp/sglang-release.patch; \
    test "$(git write-tree)" = "${QWEN38_SGLANG_EFFECTIVE_TREE}"; \
    uv run --no-project --python /opt/sglang/bin/python python -m compileall -q \
      python/sglang/kernels \
      python/sglang/srt/configs/qwen4_exp.py \
      python/sglang/srt/layers/attention/linear/kernels/gdn_flashinfer.py \
      python/sglang/srt/layers/attention/qsa \
      python/sglang/srt/layers/attention/qwen_sparse_attn_backend.py \
      python/sglang/srt/mem_cache/ple_state_pool.py \
      python/sglang/srt/mem_cache/qsa_kv_pool.py \
      python/sglang/srt/models/qwen4_exp.py \
      python/sglang/srt/models/qwen4_exp_mtp.py; \
    uv run --no-project --python /opt/sglang/bin/python python -c "from sglang.srt.configs.qwen4_exp import Qwen4ExpConfig; from sglang.srt.models.qwen4_exp import Qwen4ExpForConditionalGeneration; print(Qwen4ExpConfig.model_type, Qwen4ExpForConditionalGeneration.__name__)"; \
    uv run --no-project --python /opt/sglang/bin/python python -c "from sglang.srt.speculative import spec_utils; assert callable(spec_utils.get_exec)"; \
    uv run --no-project --python /opt/sglang/bin/python python -m pytest -q \
      test/registered/unit/mem_cache/test_qsa_compressed_addressing.py \
      test/registered/unit/server_args/test_server_args.py::TestPrepareServerArgs::test_ple_embedding_offload_rejects_generic_weight_offload \
      test/registered/unit/models/test_qwen4_exp_mtp.py; \
    uv run --no-project --python /opt/sglang/bin/python python -c "from unittest.mock import patch; import pytest; import sglang.srt.server_args as server_args_module; cuda_patch = patch.object(server_args_module, 'is_cuda', return_value=True); cuda_patch.start(); raise SystemExit(pytest.main(['-q', 'test/registered/unit/test_model_overrides.py::TestGoldenModelOverrides::test_qwen4_ple_offload_default']))"; \
    rm /tmp/sglang-release.patch

RUN set -e; \
    uv run --no-project --python /opt/sglang/bin/python python -c "import importlib.util; import flashinfer; import flashinfer_cubin; assert flashinfer.__version__ == '${QWEN38_FLASHINFER_VERSION}', flashinfer.__version__; assert flashinfer.__git_commit__ == '${QWEN38_FLASHINFER_MAIN_HEAD}', flashinfer.__git_commit__; assert flashinfer_cubin.__version__ == '${QWEN38_FLASHINFER_VERSION}', flashinfer_cubin.__version__; assert flashinfer_cubin.__git_version__ == '${QWEN38_FLASHINFER_MAIN_HEAD}', flashinfer_cubin.__git_version__; assert importlib.util.find_spec('flashinfer_jit_cache') is None; print('flashinfer', flashinfer.__version__, flashinfer.__git_commit__, 'cubin', flashinfer_cubin.__version__, flashinfer_cubin.__git_version__, 'jit-cache=source')"

ENV SGLANG_BUILD_COMMIT=${QWEN38_SGLANG_MAIN_HEAD} \
    SGLANG_BUILD_TREE=${QWEN38_SGLANG_EFFECTIVE_TREE} \
    FLASHINFER_VERSION=${QWEN38_FLASHINFER_VERSION} \
    FLASHINFER_BUILD_COMMIT=${QWEN38_FLASHINFER_MAIN_HEAD} \
    FLASHINFER_CUDA_ARCH_LIST=12.0f
LABEL org.opencontainers.image.title="sglang-qwen38-flash-next-sm120" \
      org.opencontainers.image.description="SGLang for Qwen3.8-Flash-Next FP8 on dual RTX PRO 6000 Blackwell (SM120)" \
      org.opencontainers.image.source=${IMAGE_SOURCE} \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version=${QWEN38_RELEASE_VERSION} \
      org.opencontainers.image.revision=${IMAGE_SOURCE_REVISION} \
      ai.release.candidate=rc.${QWEN38_RELEASE_CANDIDATE} \
      ai.release.cache-schema=${QWEN38_CACHE_SCHEMA} \
      ai.hardware.target-architecture="sm120" \
      ai.model.repository="Qwen/Qwen3.8-Flash-Next-FP8" \
      ai.model.revision=${QWEN38_MODEL_REVISION} \
      ai.sglang.base.head=${QWEN38_SGLANG_BASE_HEAD} \
      ai.sglang.main.head=${QWEN38_SGLANG_MAIN_HEAD} \
      ai.sglang.main.tree=${QWEN38_SGLANG_MAIN_TREE} \
      ai.sglang.pr36497.head=${QWEN38_SGLANG_PR36497_HEAD} \
      ai.sglang.pr36556.head=${QWEN38_SGLANG_PR36556_HEAD} \
      ai.sglang.integration.head=${QWEN38_SGLANG_INTEGRATION_HEAD} \
      ai.sglang.effective.tree=${QWEN38_SGLANG_EFFECTIVE_TREE} \
      ai.flashinfer.version=${QWEN38_FLASHINFER_VERSION} \
      ai.flashinfer.main.head=${QWEN38_FLASHINFER_MAIN_HEAD} \
      ai.flashinfer.main.tree=${QWEN38_FLASHINFER_MAIN_TREE}
