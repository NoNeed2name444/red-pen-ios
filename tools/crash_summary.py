#!/usr/bin/env python3
# Why the app died, in a few lines of the CI log, from its crash reports
# (app-build.yml's "Crash reports of the app" step, T0205):
#
#   python3 -I tools/crash_summary.py <report> [<report> ...]
#
# Every line starts "APP-CRASH ", and there are at most 40 in all.
# A .ips report (a one-line JSON header, then a JSON body) gives:
#   the file, the process and when it died;
#   the exception's type, signal and codes (and subtype, when there is one);
#   the termination's namespace and indicator, and what ended it;
#   the message the app left (Application Specific Information), if any;
#   the faulting thread's top 12 frames, "<image> <symbol>+<offset>", or
#   "<image> +0x<offset in the image>" where the frame has no symbol.
# A legacy .crash text report gives its process and date, its Exception Type,
# Exception Codes and Termination Reason lines, and the first 12 lines of the
# crashed thread. Which of the two a file is, is read from its content.
# A report that cannot be read gets one line saying so. The exit is always 0:
# this explains a red run, it never makes one. The report's own paths (the
# process path, each image's path) are left out: they name the runner's home;
# file and image names stand for them.
# Standard library only.
import json
import os
import re
import sys

PREFIX = 'APP-CRASH '
MAX_LINES = 40
FRAMES = 12
WIDTH = 240          # the longest line printed, prefix included
MAX_BYTES = 16 << 20  # a crash report is well under 1 MB


def one_line(value):
    """Printable text on one line, cut to fit WIDTH (a run of spaces becomes one)."""
    text = re.sub(r'\s+', ' ', re.sub(r'[\x00-\x08\x0b-\x1f\x7f]', '', str(value))).rstrip()
    room = WIDTH - len(PREFIX)
    return text if len(text) <= room else text[:room - 3] + '...'


def unreadable(name, why):
    return [f'{name}: could not read it ({why})']


def image_name(images, index):
    if isinstance(index, int) and 0 <= index < len(images) and isinstance(images[index], dict):
        image = images[index]
        name = image.get('name') or os.path.basename(str(image.get('path') or ''))
        if name:
            return name
    return '???'


def frame_text(frame, images):
    if not isinstance(frame, dict):
        return '???'
    image = image_name(images, frame.get('imageIndex'))
    symbol = frame.get('symbol')
    if symbol:
        where = frame.get('symbolLocation')
        return f'{image} {symbol}+{where}' if isinstance(where, int) else f'{image} {symbol}'
    offset = frame.get('imageOffset')
    return f'{image} +0x{offset:x}' if isinstance(offset, int) else f'{image} +0x?'


def summarise_ips(name, text):
    head, _, rest = text.partition('\n')
    try:
        header = json.loads(head)
    except ValueError:
        header = None
    if header is None:
        # no header line: the whole file as one JSON object
        try:
            header, body = {}, json.loads(text)
        except ValueError as error:
            return unreadable(name, f'not JSON: {error}')
    elif rest.strip():
        try:
            body = json.loads(rest)
        except ValueError as error:
            said = header.get('name') or header.get('app_name') if isinstance(header, dict) else None
            return unreadable(name, f'the body after the header is not JSON: {error}'
                              + (f'; the header names {said}' if said else ''))
    else:
        header, body = {}, header
    if not isinstance(header, dict) or not isinstance(body, dict):
        return unreadable(name, 'not a JSON object')
    if not any(key in body for key in ('exception', 'termination', 'threads', 'procName')):
        return unreadable(name, 'no exception, termination or threads in it')

    process = body.get('procName') or header.get('name') or header.get('app_name') or '?'
    info = body.get('bundleInfo')
    bundle = (info.get('CFBundleIdentifier') if isinstance(info, dict) else None) or header.get('bundleID')
    when = header.get('timestamp') or body.get('captureTime') or '?'
    lines = [f'{name}: {process}' + (f' ({bundle})' if bundle else '') + f' at {when}']

    exception = body.get('exception')
    if isinstance(exception, dict):
        line = f"exception {exception.get('type', '?')}"
        if exception.get('signal'):
            line += f" ({exception['signal']})"
        if exception.get('codes'):
            line += f", codes {exception['codes']}"
        for key in ('subtype', 'message'):
            if exception.get(key):
                line += f', {exception[key]}'
        lines.append(line)
    else:
        lines.append('exception: none in the report')

    termination = body.get('termination')
    if isinstance(termination, dict):
        line = f"termination {termination.get('namespace', '?')}"
        if termination.get('indicator'):
            line += f", {termination['indicator']}"
        elif isinstance(termination.get('code'), int):
            line += f", code 0x{termination['code']:x}"
        if termination.get('byProc'):
            line += f", by {termination['byProc']}"
        reasons = termination.get('reasons')
        if isinstance(reasons, list) and reasons:
            line += ': ' + ' | '.join(str(r) for r in reasons)
        lines.append(line)
    else:
        lines.append('termination: none in the report')

    # the app's last words: a Swift fatal error's message lands here
    asi = body.get('asi')
    if isinstance(asi, dict):
        said = [(image, str(m)) for image, messages in asi.items()
                for m in (messages if isinstance(messages, list) else [messages])]
        for image, message in said[:2]:
            lines.append(f'message ({image}): {message}')

    threads = body.get('threads') if isinstance(body.get('threads'), list) else []
    index = body.get('faultingThread')
    if not (isinstance(index, int) and 0 <= index < len(threads)):
        index = next((i for i, t in enumerate(threads) if isinstance(t, dict) and t.get('triggered')), None)
    if index is None or not isinstance(threads[index], dict):
        lines.append('faulting thread: not in the report')
        return lines
    thread = threads[index]
    label = thread.get('queue') or thread.get('name')
    frames = thread.get('frames') if isinstance(thread.get('frames'), list) else []
    images = body.get('usedImages') if isinstance(body.get('usedImages'), list) else []
    lines.append(f'faulting thread {index}' + (f' ({label})' if label else '') + f', {len(frames)} frames:')
    for k, frame in enumerate(frames[:FRAMES]):
        lines.append(f'{k:2d} {frame_text(frame, images)}')
    if len(frames) > FRAMES:
        lines.append(f'   ({len(frames) - FRAMES} more frames in the report)')
    return lines


def summarise_crash(name, text):
    fields = {}
    for line in text.splitlines():
        key, sep, value = line.partition(':')
        if sep and key.strip() in ('Process', 'Date/Time', 'Exception Type', 'Exception Codes',
                                   'Termination Reason') and key.strip() not in fields:
            fields[key.strip()] = value.strip()
    rows = text.splitlines()
    crashed = next((i for i, row in enumerate(rows) if re.match(r'Thread \d+ Crashed', row)), None)
    if crashed is None and not any(k in fields for k in ('Exception Type', 'Termination Reason')):
        return unreadable(name, 'no Exception Type, Termination Reason or crashed thread in it')
    lines = [f"{name}: {fields.get('Process', '?')} at {fields.get('Date/Time', '?')}"]
    for key in ('Exception Type', 'Exception Codes', 'Termination Reason'):
        if key in fields:
            lines.append(f'{key}: {fields[key]}')
    if crashed is None:
        lines.append('crashed thread: not in the report')
        return lines
    lines.append(rows[crashed])
    taken = 0
    for row in rows[crashed + 1:]:
        if not row.strip() or taken == FRAMES:
            break
        lines.append(row)
        taken += 1
    return lines


def summarise(path):
    name = one_line(os.path.basename(path)) or '?'
    try:
        with open(path, 'rb') as handle:
            data = handle.read(MAX_BYTES + 1)
    except OSError as error:
        return unreadable(name, error.strerror or type(error).__name__)
    if len(data) > MAX_BYTES:
        return unreadable(name, f'larger than {MAX_BYTES >> 20} MB')
    text = data.decode('utf-8', errors='replace').lstrip('﻿')
    if not text.strip():
        return unreadable(name, 'empty')
    try:
        if text.lstrip().startswith('{'):
            return summarise_ips(name, text)
        return summarise_crash(name, text)
    except Exception as error:  # a report shaped in a way not foreseen
        return unreadable(name, f'{type(error).__name__}: {error}')


def main(paths):
    lines = []
    for path in paths:
        lines.extend(summarise(path))
    if not paths:
        lines.append('no crash reports given')
    lines = [one_line(line) for line in lines]
    if len(lines) > MAX_LINES:
        cut = len(lines) - (MAX_LINES - 1)
        lines = lines[:MAX_LINES - 1] + [f'({cut} more lines cut; the reports themselves hold them)']
    for line in lines:
        print(PREFIX + line)


if __name__ == '__main__':
    try:
        sys.stdout.reconfigure(errors='replace')
    except (AttributeError, ValueError):
        pass
    try:
        main(sys.argv[1:])
    except Exception as error:  # never a red run of its own
        print(PREFIX + one_line(f'crash_summary.py stopped: {type(error).__name__}: {error}'))
    sys.exit(0)
