"""Exercise the real app event handlers and renderer with SDL's dummy driver."""

import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from tetris import App, pygame


class AppSmokeTests(unittest.TestCase):
    def setUp(self):
        self.app = App(argparse.Namespace(headless=True, mute=True, seed=42, demo=False,
                                          frames=1, screenshot=None))

    def tearDown(self):
        pygame.quit()

    def key(self, scan, down=True):
        self.app.event(pygame.event.Event(pygame.KEYDOWN if down else pygame.KEYUP,
                                         scancode=scan, key=0, repeat=False))

    def play(self):
        self.key(pygame.KSCAN_RETURN)
        self.assertEqual(self.app.phase, "countdown")
        self.app.update(3.01)
        self.assertEqual(self.app.phase, "playing")

    def test_countdown_does_not_drop_player_two_piece(self):
        self.play()
        self.assertEqual(self.app.match.boards[1].pieces_placed, 0)
        self.key(pygame.KSCAN_RETURN, False)
        self.key(pygame.KSCAN_RETURN)
        self.assertEqual(self.app.match.boards[1].pieces_placed, 1)

    def test_both_players_move_and_drop_independently(self):
        self.play()
        self.key(pygame.KSCAN_A)
        self.key(pygame.KSCAN_RIGHT)
        self.assertEqual([b.piece.x for b in self.app.match.boards], [2, 4])
        self.key(pygame.KSCAN_SPACE)
        self.key(pygame.KSCAN_KP_ENTER)
        self.assertEqual([b.pieces_placed for b in self.app.match.boards], [1, 1])
        self.key(pygame.KSCAN_SPACE)
        self.assertEqual(self.app.match.boards[0].pieces_placed, 1)

    def test_repeat_and_release(self):
        self.play()
        self.key(pygame.KSCAN_A)
        self.app.update(0.20)
        self.assertLess(self.app.match.boards[0].piece.x, 2)
        self.key(pygame.KSCAN_A, False)
        x = self.app.match.boards[0].piece.x
        self.app.update(0.20)
        self.assertEqual(self.app.match.boards[0].piece.x, x)

    def test_pause_help_and_focus_loss_freeze_time(self):
        self.play()
        self.key(pygame.KSCAN_P)
        self.app.update(12)
        self.assertEqual(self.app.match.elapsed, 0)
        self.key(pygame.KSCAN_P)
        self.key(pygame.KSCAN_F1)
        self.app.update(12)
        self.assertEqual(self.app.match.elapsed, 0)
        self.key(pygame.KSCAN_F1)
        self.key(pygame.KSCAN_S)
        self.app.event(pygame.event.Event(pygame.WINDOWFOCUSLOST))
        self.assertEqual(self.app.phase, "paused")
        self.assertFalse(self.app.controls.pressed)
        self.key(pygame.KSCAN_ESCAPE)
        self.app.update(0.1)
        self.assertAlmostEqual(self.app.match.elapsed, 0.1)

    def test_result_and_rematch_keep_wins(self):
        self.play()
        self.app.match.boards[0].alive = False
        self.app.update(0.01)
        self.assertEqual(self.app.phase, "over")
        self.assertEqual(self.app.wins, [0, 1])
        self.app.update(1)
        self.assertEqual(self.app.wins, [0, 1])
        self.key(pygame.KSCAN_RETURN)
        self.assertEqual(self.app.phase, "countdown")
        self.assertEqual(self.app.wins, [0, 1])
        self.assertTrue(all(b.alive for b in self.app.match.boards))

    def test_render_all_screens_and_resize(self):
        out = ROOT / "artifacts"
        out.mkdir(exist_ok=True)
        for phase in ("menu", "countdown", "playing", "paused", "over"):
            self.app.phase = phase
            if phase == "over":
                self.app.match.winner = 1
            self.app.renderer.draw(self.app, self.app.display)
            pygame.image.save(self.app.renderer.surface, str(out / f"{phase}.png"))
        self.app.show_help = True
        self.app.renderer.draw(self.app, self.app.display)
        pygame.image.save(self.app.renderer.surface, str(out / "help.png"))
        self.app.show_help = False
        self.app.phase = "playing"
        self.app.display = pygame.display.set_mode((1000, 620), pygame.RESIZABLE)
        self.key(pygame.KSCAN_V)
        self.app.renderer.draw(self.app, self.app.display)
        self.assertEqual(self.app.renderer.last_viewport.width, 992)
        self.assertEqual(self.app.renderer.camera_mode, 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
