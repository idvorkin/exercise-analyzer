"""Exercise the archive script with staged snapshots and a fake successful device copy."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("pull-tracks.sh")


class PullTracksTests(unittest.TestCase):
    def test_distinct_ids_with_same_prefix_never_replace_an_archive(self):
        self.check_export("12345678-2222-2222-2222-222222222222", collision=True)

    def test_same_id_reanalyzed_as_another_exercise_keeps_the_old_track(self):
        self.check_export("12345678-1111-1111-1111-111111111111", collision=False)

    def test_a_changed_set_on_the_phone_refreshes_its_track_and_an_unchanged_one_is_left_alone(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            stage, out, bin_dir = (root / name for name in ("stage", "out", "bin"))
            for directory in (stage, out, bin_dir):
                directory.mkdir()
            fake_copy = bin_dir / "xcrun"
            fake_copy.write_text("#!/bin/sh\nexit 0\n")
            fake_copy.chmod(0o755)
            entry = "abcdef12-1111-1111-1111-111111111111"
            snapshot = stage / entry / "analysis.json"
            snapshot.parent.mkdir()
            frame = {"time": 0.0, "imageSize": [1, 1], "box": None, "pose": None}
            env = {**os.environ, "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
                   "PULL_TRACKS_STAGE": str(stage), "PULL_TRACKS_OUT": str(out)}
            run = lambda: subprocess.run(["bash", str(SCRIPT)], capture_output=True, text=True, env=env)

            snapshot.write_text(json.dumps({"exercise": "pistol-squat", "frames": [frame], "reps": []}))
            self.assertIn("archived", run().stdout)
            track = out / "pistol-squat-nodate-abcdef12.json"
            self.assertEqual(len(json.loads(track.read_text())["frames"]), 1)

            self.assertIn("0 new or refreshed", run().stdout)

            snapshot.write_text(json.dumps({"exercise": "pistol-squat", "frames": [frame, {**frame, "time": 0.1}], "reps": [{}]}))
            result = run()
            self.assertIn("refreshed", result.stdout, result.stderr)
            refreshed = json.loads(track.read_text())
            self.assertEqual(len(refreshed["frames"]), 2)
            self.assertEqual(refreshed["source"]["reps_when_saved"], 1)
            self.assertEqual(list(out.iterdir()), [track])

    def check_export(self, second, *, collision):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            stage, out, bin_dir = (root / name for name in ("stage", "out", "bin"))
            for directory in (stage, out, bin_dir):
                directory.mkdir()
            first = "12345678-1111-1111-1111-111111111111"
            saved = out / "kettlebell-swing-nodate-12345678.json"
            original = json.dumps({"source": {"recents_id": first, "exercise": "kettlebell-swing"}, "frames": []})
            saved.write_text(original)
            snapshot = stage / second / "analysis.json"
            snapshot.parent.mkdir()
            snapshot.write_text(json.dumps({"exercise": "pistol-squat", "frames": [], "reps": []}))
            fake_copy = bin_dir / "xcrun"
            fake_copy.write_text("#!/bin/sh\nexit 0\n")
            fake_copy.chmod(0o755)
            result = subprocess.run(
                ["bash", str(SCRIPT)], capture_output=True, text=True,
                env={**os.environ, "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
                     "PULL_TRACKS_STAGE": str(stage), "PULL_TRACKS_OUT": str(out)},
            )
            if collision:
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("different recents IDs", result.stderr)
                self.assertEqual(saved.read_text(), original)
                self.assertEqual(list(out.iterdir()), [saved])
            else:
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(saved.with_name(saved.stem + "-superseded.json").read_text(), original)
                exported = json.loads((out / "pistol-squat-nodate-12345678.json").read_text())
                self.assertEqual(exported["source"]["recents_id"], second)


if __name__ == "__main__":
    unittest.main()
