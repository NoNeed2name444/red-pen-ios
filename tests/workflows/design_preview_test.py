"""Exercise the workflow's actual publisher against a local Git remote.

Run: python3 tests/workflows/design_preview_test.py
The payloads are fixtures, not simulator screenshots. No network is used.
"""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest


WORKFLOW = Path(__file__).resolve().parents[2] / '.github/workflows/design-preview.yml'


def publisher():
    text = WORKFLOW.read_text()
    step = text.split('      - name: Push the pictures\n', 1)[1]
    block = step.split('        run: |\n', 1)[1]
    lines = []
    for line in block.splitlines():
        if line and not line.startswith('          '):
            break
        lines.append(line[10:])
    return '\n'.join(lines) + '\n'


class PreviewPublication(unittest.TestCase):
    def git(self, *args):
        return subprocess.check_output(['git', *args], text=True).strip()

    def publish(self, root, remote, run, branch='preview/prework-20261006'):
        work = root / f'run-{run}'
        shots = work / 'out/shots/iphone'
        shots.mkdir(parents=True)
        (shots / f'{run}.png').write_bytes(b'fixture image payload')
        logs = work / 'out/logs'
        logs.mkdir()
        (logs / 'iphone-tour.log').write_text('** TEST EXECUTE SUCCEEDED **\n')
        script = publisher().replace(
            '"https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"',
            shlex.quote(str(remote)))
        path = work / 'publish.sh'
        path.write_text(script)
        env = {**os.environ, 'GH_TOKEN': 'fixture', 'GITHUB_REPOSITORY': 'fixture/repo',
               'GITHUB_REF_NAME': branch, 'GITHUB_SHA': f'fixture-{run}',
               'GITHUB_RUN_ID': run, 'GITHUB_STEP_SUMMARY': str(work / 'summary'),
               'RUNNER_TEMP': str(work)}
        return subprocess.run(['bash', '-e', '-o', 'pipefail', str(path)],
                              cwd=work, env=env, text=True, capture_output=True), work

    def test_repeated_publication_preserves_parent_and_replaces_payload(self):
        with tempfile.TemporaryDirectory(prefix='preview-history-') as tmp:
            root = Path(tmp)
            remote = root / 'remote.git'
            self.git('init', '--bare', '-q', str(remote))
            for branch, target in [('preview/prework-20261006', 'shots/prework-20261006'),
                                   ('preview/graph', 'design-preview')]:
                first, _ = self.publish(root, remote, target.replace('/', '-') + '-1', branch)
                self.assertEqual(first.returncode, 0, first.stderr)
                before = self.git('--git-dir', str(remote), 'rev-parse', target)
                second_run = target.replace('/', '-') + '-2'
                second, _ = self.publish(root, remote, second_run, branch)
                self.assertEqual(second.returncode, 0, second.stderr)
                after = self.git('--git-dir', str(remote), 'rev-parse', target)
                self.assertNotEqual(before, after)
                self.assertEqual(self.git('--git-dir', str(remote), 'rev-parse', after + '^'), before)
                self.assertEqual(self.git('--git-dir', str(remote), 'rev-list', '--count', target), '2')
                files = self.git('--git-dir', str(remote), 'ls-tree', '-r', '--name-only', target).splitlines()
                self.assertIn(f'shots/iphone/{second_run}.png', files)
                self.assertFalse(any(name.endswith('-1.png') for name in files))
                readme = self.git('--git-dir', str(remote), 'show', f'{target}:README.md')
                self.assertIn(f'Commit fixture-{second_run}', readme)

    def test_remote_error_stops_before_creating_replacement_commit(self):
        with tempfile.TemporaryDirectory(prefix='preview-remote-error-') as tmp:
            root = Path(tmp)
            result, work = self.publish(root, root / 'missing.git', 'error')
            self.assertNotEqual(result.returncode, 0)
            head = subprocess.run(['git', '-C', str(work / 'out'), 'rev-parse', '--verify', 'HEAD'],
                                  capture_output=True)
            self.assertNotEqual(head.returncode, 0)


if __name__ == '__main__':
    unittest.main()
