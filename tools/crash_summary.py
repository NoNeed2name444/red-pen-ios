#!/usr/bin/env python3
# Why the app died, in a few lines of the CI log, from its crash reports
# (app-build.yml's "Crash reports of the app" step, T0205):
#
#   python3 -I tools/crash_summary.py <report> [<report> ...]
#
# Every line starts "APP-CRASH ", and there are at most 40 in all, shared
# evenly between the reports: each keeps at least its first two lines (the
# file, process and time; then the exception), and when there are too many
# reports even for that, the last line says how many were left out.
# A .ips report (a one-line JSON header, then a JSON body) gives:
#   the file, the process and when it died;
#   the exception's type, signal and codes (and subtype, when there is one);
#   the termination's namespace and indicator, and what ended it;
#   the message the app left (Application Specific Information), if any;
#   the faulting thread's top 12 frames, "<image> <symbol>+<offset>", or
#   "<image> +0x<offset in the image>" where the frame has no symbol.
# A text report (a legacy .crash, or a .ips whose body after the header is
# text, as a CPU limit report's is) gives its process and date, the Event,
# Action taken, CPU, Exception Type, Exception Codes and Termination Reason
# lines it has, and the first 12 lines of the crashed thread. Which kind a
# file is, is read from its content.
# A report that cannot be read gets one line saying so. The exit is always 0:
# this explains a red run, it never makes one.
# Paths: the process path and the images' paths are never printed (an image
# is named by its name), and any absolute path in what is printed (a message,
# a reason, a line of a text report) is cut to its last part, so no line names
# the runner's home.
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
# an absolute path's folders: "/" or "~/" not inside a word, a URL or "a/b",
# then one or more "<name>/"; what follows (the file's name) is kept
FOLDERS = re.compile(r'''(?<![\w:/.~])~?/(?:[^/\s'"()<>]+/)+''')
# the lines a text report is read for, and the ones of them printed, in order
TEXT_KEYS = ('Process', 'Command', 'Date/Time', 'Event', 'Action taken', 'CPU',
             'Exception Type', 'Exception Codes', 'Termination Reason')
TEXT_SHOWN = ('Event', 'Action taken', 'CPU', 'Exception Type', 'Exception Codes',
              'Termination Reason')


def one_line(value):
    """Printable text on one line, absolute paths cut to their last part, cut
    to fit WIDTH (a run of spaces becomes one)."""
    text = re.sub(r'[\x00-\x08\x0b-\x1f\x7f]', '', str(value))
    text = re.sub(r'\s+', ' ', FOLDERS.sub('', text)).rstrip()
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
        if not rest.lstrip().startswith('{'):
            # a text body (a CPU limit report's), read like a legacy report
            return summarise_text(name, rest, header)
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
    lines.append(f'faulting thread {index}' + (f' ({label})' if label else '')
                 + f", {len(frames)} frame{'' if len(frames) == 1 else 's'}:")
    for k, frame in enumerate(frames[:FRAMES]):
        lines.append(f'{k:2d} {frame_text(frame, images)}')
    if len(frames) > FRAMES:
        lines.append(f'   ({len(frames) - FRAMES} more frames in the report)')
    return lines


def summarise_text(name, text, header=None):
    header = header if isinstance(header, dict) else {}
    fields = {}
    for line in text.splitlines():
        key, sep, value = line.partition(':')
        key = key.strip()
        if sep and key in TEXT_KEYS and key not in fields:
            fields[key] = value.strip()
    rows = text.splitlines()
    crashed = next((i for i, row in enumerate(rows) if re.match(r'Thread \d+ Crashed', row)), None)
    said = header.get('name') or header.get('app_name')
    if crashed is None and not any(k in fields for k in ('Exception Type', 'Termination Reason', 'Event')):
        return unreadable(name, 'no Exception Type, Termination Reason, Event or crashed thread in it'
                          + (f'; the header names {said}' if said else ''))
    process = fields.get('Process') or fields.get('Command') or said or '?'
    when = fields.get('Date/Time') or header.get('timestamp') or '?'
    lines = [f'{name}: {process} at {when}']
    for key in TEXT_SHOWN:
        if key in fields:
            lines.append(f'{key}: {fields[key]}')
    if crashed is None:
        if 'Event' not in fields:  # a resource report has no crashed thread
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
    text = data.decode('utf-8', errors='replace').lstrip('\ufeff')
    if not text.strip():
        return unreadable(name, 'empty')
    try:
        if text.lstrip().startswith('{'):
            return summarise_ips(name, text)
        return summarise_text(name, text)
    except Exception as error:  # a report shaped in a way not foreseen
        return unreadable(name, f'{type(error).__name__}: {error}')


def share(blocks, budget=MAX_LINES):
    """The reports' lines, at most `budget` of them, shared evenly: each report
    keeps its first two, then one more each in turn while room is left; the
    last line says what was cut."""
    total = sum(len(block) for block in blocks)
    if total <= budget:
        return [line for block in blocks for line in block]
    room = budget - 1
    shown = blocks[:max(1, room // 2)]
    keep = [min(2, len(block)) for block in shown]
    left = room - sum(keep)
    while left > 0:
        grown = False
        for i, block in enumerate(shown):
            if left > 0 and keep[i] < len(block):
                keep[i] += 1
                left -= 1
                grown = True
        if not grown:
            break
    lines = [line for block, k in zip(shown, keep) for line in block[:k]]
    hidden = len(blocks) - len(shown)
    note = f'({total - len(lines)} more lines cut'
    note += f', {hidden} reports not shown at all' if hidden else ''
    return lines + [note + '; the reports themselves hold them)']


def main(paths):
    blocks = [[one_line(line) for line in summarise(path)] for path in paths]
    for line in share(blocks or [['no crash reports given']]):
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
