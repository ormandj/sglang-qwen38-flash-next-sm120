# v0.1.0-rc.9 validation

## Immutable candidate

- Tested image digest:
  `sha256:ce30879b5d473967fe3f0f6947a63efe2ea971dc47fd086ac0db5c54fb0c8387`
- Model revision: `bcd9f01ddc9cff2316eb84281bebcd5b058bddce`
- SGLang main: `7f27bf470824f452a34e866d22ab5e332a23e26f`
- Effective SGLang tree: `1cf4eb136f470e0dba5eed62d107d16e6bc3ed85`
- FlashInfer main: `e4b7fa4b7c3ba5e17286d9c59f2bcf2ca07e0a6d`
- AIPerf: `6ed4823d127b3a6d12c63fb8c2ca5eff13f9ba23`
- Runtime: TP2/EP2, NEXTN 3/1/4, native 262,144 context, HiCache off.

## Functional smoke

The exact candidate passed health, model discovery, text generation, separated
reasoning, forced tool call, and image-input checks. It remained Ready with
zero restarts after the performance and quality screens.

## Full GSM8K

The pinned AIPerf grader ran all 1,319 GSM8K test questions once:

| Setting | Value |
|---|---:|
| Concurrency | 16 |
| Temperature | 0 |
| Seed | 42 |
| Response cap | 16,384 tokens |
| Duration | 609.57 seconds |
| Correct | 1,264 |
| Incorrect | 55 |
| Accuracy | 95.83% |
| Request errors | 0 |
| Response-cap hits | 0 |
| Output-token range | 35-11,398 |

Every response contained non-empty separated reasoning and final output. None
contained GSM8K's literal `####` answer marker. AIPerf therefore labeled all
1,319 records `unparsed` and used its documented last-number fallback; that
fallback extracted a non-empty answer for every response and produced the
1,264/1,319 score.

Raw artifact hashes:

| Artifact | SHA-256 |
|---|---|
| Full `SHA256SUMS` inventory | `3e86a84ef0ea2c8abe72e6c619b8e105fae536512803a63adf4bf9b07082c5e9` |
| Aggregate accuracy CSV | `87daa4d2d11646544926cdf8e000679a9e4c2e83fb898c12e4eb926ca3d60cba` |
| Per-question accuracy JSONL | `25ca13f00dacdb2bcfd12a6f34632149fbdc279dd5798d953d9eac7c9d464a91` |
| Outputs JSON | `03d841549528570bc14baa5297cf9a3a27862ff6cf068df841f0a4ddce0ee35b` |
| AIPerf profile summary | `9321f35acbe798728959c56a153d62210a22b84cc23e490b693516cf56c55739` |

## Performance status

### Five-run decode panel

The exact candidate ran the frozen DSV4F `publication` workload on one
unchanged server process: 16,384 requested input tokens, 4,096 forced output
tokens, temperature zero, the fixed five-seed panel, and five valid repetitions
at every supported concurrency. All 25 C1-C16 repetitions passed the occupancy,
queue, prefill-counter, context-window, duration, and sample-count controls with
zero request errors.

`Forward/s` is the arithmetic-neutral engine clock. `Forced output tok/s`
includes the model's path-dependent MTP acceptance, while ITL is the client
inter-token latency. These fixed-window values are engineering regression
signals rather than expected interactive or application throughput.

| C | Forward/s median | Forced output tok/s median | ITL median | Output/forward/request median |
|---:|---:|---:|---:|---:|
| 1 | 74.355 | 196.3 | 5.155 ms | 2.611 |
| 2 | 61.806 | 336.6 | 6.150 ms | 2.746 |
| 4 | 47.059 | 508.4 | 8.123 ms | 2.664 |
| 8 | 33.163 | 758.8 | 11.030 ms | 2.876 |
| 16 | 23.573 | 1,062.1 | 17.010 ms | 2.808 |

C1 had the largest output-rate variance: 6.60% sample CV. Its forward-rate CV
was only 0.40%, locating that variation in MTP acceptance rather than the
underlying engine clock.

### Cold prefill

The same process completed five cache-busted C1 requests at every frozen
prefill length. All 20 requests passed cold-cache, token-count, and compute
controls with zero errors.

| Target | Prompt tok/s | Median TTFT | Requests |
|---:|---:|---:|---:|
| 8K | 9,428.0 | 871.2 ms | 5 |
| 32K | 11,392.0 | 2,885.7 ms | 5 |
| 64K | 11,542.9 | 5,676.4 ms | 5 |
| 128K | 11,252.0 | 11,605.2 ms | 5 |

### DSV4F reference comparison

The table below compares absolute medians with the retained HiCache-disabled
DeepSeek V4 Flash `0.8.1-rc10` five-run panel from the same frozen AIPerf
revision. This is not a paired geometric comparison.

| C | Qwen forward/s change | Qwen forced-output change | Qwen ITL change |
|---:|---:|---:|---:|
| 1 | +14.2% | -39.4% | +61.8% |
| 2 | +25.2% | -29.3% | +41.7% |
| 4 | +41.0% | -22.4% | +26.3% |
| 8 | +42.4% | -18.4% | +13.4% |
| 16 | +30.9% | -24.6% | +20.9% |

Qwen's forward clock was faster at every supported cell, but its MTP-3
acceptance produced only 2.61-2.88 output tokens per forward per request, so
acceptance-weighted output throughput was lower. Cold-prefill rate was 19.3%,
29.3%, 36.1%, and 41.2% higher at 8K, 32K, 64K, and 128K respectively.

### C32 capacity disposition

C32 is unsupported for the fixed test shape under this runtime envelope. The
client completed 32/32 requests with zero errors, but the requests required
657,006 prompt-plus-output tokens while the server exposed a 580,032-token
pool. At most 26 requests ran concurrently and six normally remained queued.
The canonical analyzer therefore rejected the attempt with
`no samples matched the average-context window`; it is retained as capacity
evidence and is not counted as a performance repetition.

### Evidence

The complete raw bundle's `SHA256SUMS` manifest hashes to
`0797bb93a90b915d29ccacb068f1ca10bd8a0e62c1c87216a1bd889860019f53`.
The exact machine-readable supported-panel aggregate is published at
[`evidence/v0.1.0-rc.9/publication-summary.json`](evidence/v0.1.0-rc.9/publication-summary.json)
and hashes to
`3772dddaf9b0caf6027d09ca084df2862daedbb3c0961c3b8015c19a3b47205c`.

Near-native-context, non-speculative, AgentX, and human release-review gates
remain pending. This repository is therefore an experimental source release,
not a stable or cross-hardware performance claim.
