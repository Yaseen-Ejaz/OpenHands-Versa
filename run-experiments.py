import json
import random
import subprocess
import typing
from datetime import datetime, timezone
from pathlib import Path
from typing import List, TypedDict


class Color:
    # Styles
    BOLD = '1'
    UNDERLINE = '4'
    # Foreground
    RED = '31'
    GREEN = '32'
    YELLOW = '33'
    BLUE = '34'
    WHITE = '37'
    # Background
    BG_RED = '41'
    BG_GREEN = '42'
    BG_YELLOW = '43'
    BG_BLUE = '44'


def notice(text, *args):
    """
    Usage: log("Error", Color.RED, Color.BG_YELLOW, Color.BOLD)
    """
    if not args:
        return text
    codes = ';'.join(args)
    return print(f'\n\n\033[{codes}m{text}\033[0m\n\n')


log_dir = Path.cwd() / 'jack' / 'ocr' / 'logs'
preds_dir = Path.cwd() / 'jack' / 'ocr' / 'preds'

log_dir.mkdir(parents=True, exist_ok=True)
preds_dir.mkdir(parents=True, exist_ok=True)

todo_json_filepath = Path.cwd() / 'todo6.json'

ERROR_TRIGGER = (
    'litellm.exceptions.RateLimitError: litellm.RateLimitError: AnthropicException'
)


class TodoJson(TypedDict):
    todo: List[str]
    pending_verification: List[str]
    rate_limited: List[str]
    failed_but_should_retry: List[str]
    success: List[str]
    fail: List[str]


def now_utc() -> str:
    dt = datetime.now(timezone.utc)
    timestamp = dt.strftime('%Y-%m-%d_%H-%M-%S-') + f'{dt.microsecond // 1000:03d}Z'
    return timestamp


def iterate_instances():
    while True:
        with open(todo_json_filepath, 'r') as f:
            todo_json = json.load(f)
            todo_json = typing.cast(TodoJson, todo_json)

        n_remaining_instances = len(todo_json['todo'])
        if n_remaining_instances == 0:
            break

        instance = todo_json['todo'].pop(random.randrange(n_remaining_instances))
        todo_json['pending_verification'].append(instance)

        with open(todo_json_filepath, 'w') as f:
            json.dump(todo_json, f, indent=4)

        yield instance


def add_instance_to_rate_limited(instance: str) -> None:
    with open(todo_json_filepath, 'r') as f:
        todo_json = json.load(f)
        todo_json = typing.cast(TodoJson, todo_json)

    try:
        todo_json['pending_verification'].remove(instance)
    except:
        notice(
            f'Could not find {instance} in pending_verification',
            Color.BG_RED,
            Color.WHITE,
            Color.BOLD,
        )

    todo_json['rate_limited'].append(instance)

    with open(todo_json_filepath, 'w') as f:
        json.dump(todo_json, f, indent=4)


def docker_prune():
    notice('Pruning Docker resources', Color.GREEN, Color.WHITE, Color.BOLD)
    commands = [
        ['docker', 'image', 'prune', '-a', '-f'],
        ['docker', 'container', 'prune', '-f'],
    ]

    for cmd in commands:
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            notice(
                f'Docker prune successful: {" ".join(cmd)}',
                Color.GREEN,
                Color.WHITE,
                Color.BOLD,
            )
        else:
            notice(
                f'Docker prune unsuccessful (return code {result.returncode}): {" ".join(cmd)}\n\n{result.stderr}',
                Color.RED,
                Color.WHITE,
                Color.BOLD,
            )


def run_instances() -> None:
    for instance_id in iterate_instances():
        notice(f'Starting instance {instance_id}', Color.GREEN, Color.WHITE, Color.BOLD)
        log_filepath = log_dir / f'{now_utc()}-{instance_id}.log'

        bash = subprocess.Popen(
            ['/bin/bash', 'go.sh', 'full', '--instance', f'{instance_id}'],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )

        with open(log_filepath, 'w') as f:
            # Read line by line as it happens
            for line in iter(bash.stdout.readline, ''):
                f.write(line)
                f.flush()
                print(line, end='')

                if ERROR_TRIGGER in line:
                    notice(
                        'Rate limit detected. Terminating...',
                        Color.BG_RED,
                        Color.WHITE,
                        Color.BOLD,
                    )
                    add_instance_to_rate_limited(instance_id)
                    bash.terminate()
                    break

        bash.stdout.close()
        rc_bash = bash.wait()

        docker_prune()

        notice(f'{rc_bash=}', Color.BG_BLUE, Color.WHITE, Color.BOLD)


if __name__ == '__main__':
    run_instances()
