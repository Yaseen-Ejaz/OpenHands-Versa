export SEARCH_API_KEY=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
export ITERATIVE_EVAL_MODE=true
POETRY_BIN=$(which poetry) \
    sudo -E bash evaluation/benchmarks/swe_bench/scripts/run_infer.sh \
        llm.gpt \
        HEAD \
        CodeActAgent \
        10 \
        50 \
        1 \
        princeton-nlp/SWE-bench_Multimodal \
        test
