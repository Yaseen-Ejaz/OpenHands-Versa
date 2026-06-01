#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ############################################################################################################################################# #
#  █████  ██████   ██████  ██    ██ ███    ███ ███████ ███    ██ ████████     ██████  ███████ ███████  █████  ██    ██ ██      ████████ ███████ #
# ██   ██ ██   ██ ██       ██    ██ ████  ████ ██      ████   ██    ██        ██   ██ ██      ██      ██   ██ ██    ██ ██         ██    ██      #
# ███████ ██████  ██   ███ ██    ██ ██ ████ ██ █████   ██ ██  ██    ██        ██   ██ █████   █████   ███████ ██    ██ ██         ██    ███████ #
# ██   ██ ██   ██ ██    ██ ██    ██ ██  ██  ██ ██      ██  ██ ██    ██        ██   ██ ██      ██      ██   ██ ██    ██ ██         ██         ██ #
# ██   ██ ██   ██  ██████   ██████  ██      ██ ███████ ██   ████    ██        ██████  ███████ ██      ██   ██  ██████  ███████    ██    ███████ #
# ###############################################################################################################################################

BASE_DIR="/home/daniel/York/Masters/EECS6444/Project/OpenHands-Versa"
VENV_NAME="oh_versa"
CONFIG_TOML_REL="evaluation/benchmarks/swe_bench/config.toml"

MODEL_SPEC_DEFAULT="llm.claude4"
REV_DEFAULT="HEAD"
AGENT_DEFAULT="CodeActAgent"
N_WORKERS_DEFAULT="10"
N_EXAMPLES_DEFAULT="50"
SEED_DEFAULT="1"
DATASET_DEFAULT="princeton-nlp/SWE-bench_Multimodal"
SPLIT_DEFAULT="test"

# Secrets via env
: "${SEARCH_API_KEY:=$(head -n 1 'tavily-api-key.txt')}"
: "${SWE_BENCH_API_KEY:=$(shuf -n 1 'sb-cli-api-key.txt')}"

# ####################################################### #
# ██   ██ ███████ ██      ██████  ███████ ██████  ███████ #
# ██   ██ ██      ██      ██   ██ ██      ██   ██ ██      #
# ███████ █████   ██      ██████  █████   ██████  ███████ #
# ██   ██ ██      ██      ██      ██      ██   ██      ██ #
# ██   ██ ███████ ███████ ██      ███████ ██   ██ ███████ #
# ####################################################### #

# Exits with an error message
die() { echo "ERROR: $*" >&2; exit 1; }

# Echo a message in a log format
log() { echo "[*] $*" >&2; }

# Check if a command name exists as a command, exit if it does not exist
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

# Trap errors that happen in the script and print the line number
on_err() {
    local code=$?
    echo "ERROR: command failed (exit=$code) at line $1: ${BASH_COMMAND}" >&2
    exit "$code"
}
trap 'on_err $LINENO' ERR

# Convert a local path to an absolute path
abs_path() {
    local base="$1" p="$2"
    if [[ "$p" == /* ]]; then
        printf "%s\n" "$p"
    else
        printf "%s/%s\n" "$base" "$p"
    fi
}

# ############################################################################################################################### #
# ██    ██ ███████  █████   ██████  ███████     ██████  ███████ ███████  ██████ ██████  ██ ██████  ████████ ██  ██████  ███    ██ #
# ██    ██ ██      ██   ██ ██       ██          ██   ██ ██      ██      ██      ██   ██ ██ ██   ██    ██    ██ ██    ██ ████   ██ #
# ██    ██ ███████ ███████ ██   ███ █████       ██   ██ █████   ███████ ██      ██████  ██ ██████     ██    ██ ██    ██ ██ ██  ██ #
# ██    ██      ██ ██   ██ ██    ██ ██          ██   ██ ██           ██ ██      ██   ██ ██ ██         ██    ██ ██    ██ ██  ██ ██ #
#  ██████  ███████ ██   ██  ██████  ███████     ██████  ███████ ███████  ██████ ██   ██ ██ ██         ██    ██  ██████  ██   ████ #
# ############################################################################################################################### #

usage() {
  cat >&2 <<EOF
Usage:
    $(basename "$0") infer  --instance <ID> [options]
    $(basename "$0") submit --out-jsonl <path> --translated <path> --pred <path> [--run-id <id>] [options]

Commands:
    infer
        1) cd
        2) check venv
        3) set instance in config.toml
        4) run inference
        5) fix ownership (optional)

    submit
        6) translate output file
        7) submit prediction

Common options:
    --base-dir <path>     (default: $BASE_DIR)
    --venv <name>         (default: $VENV_NAME)
    --dry-run             Print steps without executing

infer options:
    --instance <ID>       Required
    --no-chown            Skip ownership fix step

submit options:
    --out-jsonl <path>    Required (raw inference output .jsonl)
    --model-name <name>   Translator model_name (default: $MODEL_SPEC_DEFAULT)
    --run-id <id>         Default: "<timestamp>" (does NOT need instance)

Environment variables:
    SEARCH_API_KEY        Required for infer
    SWE_BENCH_API_KEY     Required for submit
EOF
}

# ############################################################################################################################################# #
# ██████   █████  ██████  ███████ ███████     ███████ ██    ██ ██████   ██████  ██████  ███    ███ ███    ███  █████  ███    ██ ██████  ███████ #
# ██   ██ ██   ██ ██   ██ ██      ██          ██      ██    ██ ██   ██ ██      ██    ██ ████  ████ ████  ████ ██   ██ ████   ██ ██   ██ ██      #
# ██████  ███████ ██████  ███████ █████       ███████ ██    ██ ██████  ██      ██    ██ ██ ████ ██ ██ ████ ██ ███████ ██ ██  ██ ██   ██ ███████ #
# ██      ██   ██ ██   ██      ██ ██               ██ ██    ██ ██   ██ ██      ██    ██ ██  ██  ██ ██  ██  ██ ██   ██ ██  ██ ██ ██   ██      ██ #
# ██      ██   ██ ██   ██ ███████ ███████     ███████  ██████  ██████   ██████  ██████  ██      ██ ██      ██ ██   ██ ██   ████ ██████  ███████ #
# ############################################################################################################################################# #

[[ $# -ge 1 ]] || { usage; die "Missing command (infer|submit)"; }
CMD="$1"; shift

# Defaults for args
BASE_DIR_ARG="$BASE_DIR"
VENV_NAME_ARG="$VENV_NAME"
DRY_RUN=0

# infer args
INSTANCE_ID=""
DO_CHOWN=1

# submit args
OUT_JSONL=$(find evaluation/evaluation_outputs/outputs/princeton-nlp__SWE-bench_Multimodal-test/CodeActAgent/claude-sonnet-4-20250514_maxiter_50_N_v0.28.1-no-hint-with-browsing-run_1/output.jsonl -type f -name "output.jsonl" -print -quit)
MODEL_NAME="$MODEL_SPEC_DEFAULT"
RUN_ID=""
PREDS_DIR='jack/forgotten3/preds'

# Parse flags (shared + per command)
while [[ $# -gt 0 ]]; do
    case "$1" in
        --base-dir)   BASE_DIR_ARG="${2:-}"; shift 2 ;;
        --venv)       VENV_NAME_ARG="${2:-}"; shift 2 ;;
        --dry-run)    DRY_RUN=1; shift ;;

        # infer
        --instance)   INSTANCE_ID="${2:?--instance requires a value}"; shift 2 ;;
        --no-chown)   DO_CHOWN=0; shift ;;

        # submit
        --preds-dir)    PREDS_DIR="${2:-}"; shift 2 ;;
        --out-jsonl)    OUT_JSONL="${2:-}"; shift 2 ;;
        --model-name)   MODEL_NAME="${2:-}"; shift 2 ;;
        --run-id)       RUN_ID="${2:?--run-id requires a value}"; shift 2 ;;

        -h|--help) usage; exit 0 ;;
        *) die "Unknown argument: $1 (use --help)" ;;
  esac
done

# #################################################################################################### #
# ██████  ██████  ███████  ██████  ██████  ███    ██ ██████  ██ ████████ ██  ██████  ███    ██ ███████ #
# ██   ██ ██   ██ ██      ██      ██    ██ ████   ██ ██   ██ ██    ██    ██ ██    ██ ████   ██ ██      #
# ██████  ██████  █████   ██      ██    ██ ██ ██  ██ ██   ██ ██    ██    ██ ██    ██ ██ ██  ██ ███████ #
# ██      ██   ██ ██      ██      ██    ██ ██  ██ ██ ██   ██ ██    ██    ██ ██    ██ ██  ██ ██      ██ #
# ██      ██   ██ ███████  ██████  ██████  ██   ████ ██████  ██    ██    ██  ██████  ██   ████ ███████ #
# #################################################################################################### #

need_cmd sudo
need_cmd python3
need_cmd jq

[[ -d "$BASE_DIR_ARG" ]] || die "Base dir not found: $BASE_DIR_ARG"

# ######################################## #
# ███████ ████████ ███████ ██████  ███████ #
# ██         ██    ██      ██   ██ ██      #
# ███████    ██    █████   ██████  ███████ #
#      ██    ██    ██      ██           ██ #
# ███████    ██    ███████ ██      ███████ #
# ######################################## #

# Change directory to the OH-Versa base directory
step_cd() {
    log "cd -> $BASE_DIR_ARG"
    [[ $DRY_RUN -eq 1 ]] && return 0
    cd "$BASE_DIR_ARG"
}

# Make sure this script is being run in the correct Python virtual environment
step_check_venv() {
    log "check venv (expecting '$VENV_NAME_ARG')"
    [[ $DRY_RUN -eq 1 ]] && return 0
    python3 - <<PY
import os, sys

expected = "${VENV_NAME_ARG}"
env_name = os.path.basename(sys.prefix)

if env_name != expected:
    raise SystemExit(
        f"Wrong environment: detected '{env_name}', expected '{expected}'"
    )
PY
}

# Set the instance in the config file
step_set_instance() {
    local id="$1"
    local cfg="$BASE_DIR_ARG/$CONFIG_TOML_REL"
    log "set instance -> $cfg (selected_ids = ['$id'])"
    [[ $DRY_RUN -eq 1 ]] && return 0
    local tmp
    tmp="$(mktemp)"

    # Ensure tmp is cleaned up even if setting instance fails
    cleanup_tmp() { rm -f "$tmp"; }
    trap cleanup_tmp RETURN

    printf "selected_ids = ['%s']\n" "$id" > "$tmp"
    mv "$tmp" "$cfg"
}

# Run inference with OH-Versa
step_run_infer() {
    need_cmd poetry
    [[ -n "$SEARCH_API_KEY" ]] || die "SEARCH_API_KEY is empty. Export it before running infer."

    log "run inference -> run_infer.sh (sudo -E)"
    [[ $DRY_RUN -eq 1 ]] && return 0

    export SEARCH_API_KEY
    export ITERATIVE_EVAL_MODE=true
    export POETRY_BIN="$(command -v poetry)"
    sudo -n -E \
        /bin/bash /home/daniel/York/Masters/EECS6444/Project/OpenHands-Versa/evaluation/benchmarks/swe_bench/scripts/run_infer.sh \
            "$MODEL_SPEC_DEFAULT" \
            "$REV_DEFAULT" \
            "$AGENT_DEFAULT" \
            "$N_WORKERS_DEFAULT" \
            "$N_EXAMPLES_DEFAULT" \
            "$SEED_DEFAULT" \
            "$DATASET_DEFAULT" \
            "$SPLIT_DEFAULT"
}

# Fix ownership of the evaluation outputs (since the inference command is run
# with sudo, the output files will be owned by root, so this transfers ownership
# back to the user)
step_fix_ownership() {
    if [[ $DO_CHOWN -eq 0 ]]; then
        log "fix ownership -> skipped (--no-chown)"
        return 0
    fi
    log "fix ownership -> sudo chown -R $USER:$USER ."
    [[ $DRY_RUN -eq 1 ]] && return 0
    sudo -n /bin/chown -R "$USER:$USER" /home/daniel/York/Masters/EECS6444/Project/OpenHands-Versa
}

# Translate the output file to a format understandable by SWE-Bench
step_translate() {
    [[ -n "${INSTANCE_ID:-}" ]] || die "INSTANCE_ID is empty (did you pass --instance?)"

    local out_jsonl_abs
    local translated_abs
    local tmp_jsonl

    out_jsonl_abs="$(abs_path "$BASE_DIR_ARG" "$OUT_JSONL")"
    translated_abs="$(abs_path "$BASE_DIR_ARG/$PREDS_DIR" "$INSTANCE_ID.pred")"
    tmp_jsonl="$(mktemp --suffix=.jsonl)"

    log "translate -> $out_jsonl_abs -> $translated_abs (model_name=$MODEL_NAME)"
    [[ $DRY_RUN -eq 1 ]] && return 0

    [[ -f "$out_jsonl_abs" ]] || die "Raw output jsonl not found: $out_jsonl_abs"

    # Ensure tmp_jsonl is cleaned up even if translate fails
    cleanup_tmp_jsonl() { rm -f "$tmp_jsonl"; }
    trap cleanup_tmp_jsonl RETURN

    jq -c --arg id "$INSTANCE_ID" 'select(.instance_id == $id)' "$out_jsonl_abs" > "$tmp_jsonl"

    [[ -s "$tmp_jsonl" ]] || die "No entries found for instance_id=$INSTANCE_ID"

    touch "$translated_abs"

    python3 evaluation/benchmarks/swe_bench/sb_cli_translate.py \
        --input_file "$tmp_jsonl" \
        --output_file "$translated_abs" \
        --model_name "$MODEL_NAME"

    [[ -f "$translated_abs" ]] || die "Translate step did not produce: $translated_abs"

    # Remove leading and trailing square brackets
    sed -i '1s/^\[//; $s/\]$//' "$translated_abs"
}

# Submit prediction to SWE-Bench
step_submit() {
    need_cmd sb-cli
    [[ -n "$SWE_BENCH_API_KEY" ]] || die "SWE_BENCH_API_KEY is empty. Export it before running submit."

    local pred_abs
    pred_abs="$(abs_path "$BASE_DIR_ARG/$PREDS_DIR" "$INSTANCE_ID.pred")"

    RUN_ID="$INSTANCE_ID-$(date +%Y%m%d_%H%M%S)"

    log "submit -> $pred_abs (run_id=$RUN_ID)"
    [[ $DRY_RUN -eq 1 ]] && return 0

    [[ -f "$pred_abs" ]] || die "Predictions file not found: $pred_abs"

    sb-cli submit \
        swe-bench-m \
        test \
        --predictions_path "$pred_abs" \
        --run_id "$RUN_ID" \
        --api_key "$SWE_BENCH_API_KEY"

    echo "Submission complete for $RUN_ID"
}

# ################################################################################################################################ #
#  ██████  ██████  ███    ███ ███    ███  █████  ███    ██ ██████      ██████  ██ ███████ ██████   █████  ████████  ██████ ██   ██ #
# ██      ██    ██ ████  ████ ████  ████ ██   ██ ████   ██ ██   ██     ██   ██ ██ ██      ██   ██ ██   ██    ██    ██      ██   ██ #
# ██      ██    ██ ██ ████ ██ ██ ████ ██ ███████ ██ ██  ██ ██   ██     ██   ██ ██ ███████ ██████  ███████    ██    ██      ███████ #
# ██      ██    ██ ██  ██  ██ ██  ██  ██ ██   ██ ██  ██ ██ ██   ██     ██   ██ ██      ██ ██      ██   ██    ██    ██      ██   ██ #
#  ██████  ██████  ██      ██ ██      ██ ██   ██ ██   ████ ██████      ██████  ██ ███████ ██      ██   ██    ██     ██████ ██   ██ #
# ################################################################################################################################ #

case "$CMD" in
    infer)
        [[ -n "$INSTANCE_ID" ]] || { usage; die "infer requires --instance"; }
        step_cd
        step_check_venv
        step_set_instance "$INSTANCE_ID"
        step_run_infer
        step_fix_ownership
        log "infer done."
        ;;
    translate)
        [[ -n "$OUT_JSONL" ]] || { usage; die "submit requires --out-jsonl"; }
        [[ -n "$INSTANCE_ID" ]] || { usage; die "infer requires --instance"; }
        step_cd
        step_check_venv
        step_translate
        log "submit done."
        ;;
    submit)
        [[ -n "$OUT_JSONL" ]] || { usage; die "submit requires --out-jsonl"; }
        [[ -n "$INSTANCE_ID" ]] || { usage; die "infer requires --instance"; }
        step_cd
        step_check_venv
        step_translate
        step_submit
        log "submit done."
        ;;
    full)
        [[ -n "$OUT_JSONL" ]] || { usage; die "submit requires --out-jsonl"; }
        [[ -n "$INSTANCE_ID" ]] || { usage; die "infer requires --instance"; }
        step_cd
        step_check_venv
        step_set_instance "$INSTANCE_ID"
        step_run_infer
        step_fix_ownership
        log "infer done."
        step_translate
        #step_submit
        log "submit done."
        ;;
    *)
        usage
        die "Unknown command: $CMD (expected infer|submit)"
        ;;
esac
