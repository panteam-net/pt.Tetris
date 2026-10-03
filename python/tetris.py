"""TETRIS DUEL 3D — run with Python 3.10+ and pygame-ce.

Use --headless --demo --frames 120 --screenshot artifacts/game.png for a
reproducible rendering check without opening a window.
"""

from __future__ import annotations

import argparse
from array import array
import math
import os
from pathlib import Path
import random
import sys

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
if (ROOT / ".deps").is_dir():
    sys.path.insert(0, str(ROOT / ".deps"))
os.environ["PYGAME_HIDE_SUPPORT_PROMPT"] = "1"

try:
    import pygame
except ImportError:
    raise SystemExit("Установите библиотеку: python -m pip install -r requirements.txt\n"
                     "Или откройте start.bat в папке игры.")

from engine import HIDDEN, HEIGHT, WIDTH, Match
from renderer import Renderer, SIZE


class Audio:
    """Short synthesized effects; no downloads, music files or numpy needed."""

    def __init__(self, muted=False):
        self.enabled = not muted
        self.sounds = {}
        try:
            pygame.mixer.init(frequency=22050, size=-16, channels=1, buffer=512)
            for name, notes, length in (
                ("lock", (130, 95), 0.075),
                ("clear", (523, 659, 784), 0.21),
                ("hold", (330, 440), 0.085),
                ("garbage", (196, 147, 110), 0.17),
                ("start", (392, 523, 784), 0.23),
                ("over", (523, 659, 784, 1047), 0.5),
            ):
                samples = array("h")
                count = int(22050 * length)
                segment = max(1, count // len(notes))
                for index in range(count):
                    frequency = notes[min(len(notes)-1, index // segment)]
                    local = (index % segment) / segment
                    envelope = min(1, local*20) * (1-local) ** 1.6
                    wave = math.sin(2*math.pi*frequency*index/22050)
                    samples.append(round(wave * envelope * 2700))
                self.sounds[name] = pygame.mixer.Sound(buffer=samples)
        except pygame.error:
            self.enabled = False

    def play(self, name):
        if self.enabled and name in self.sounds:
            self.sounds[name].play()

    def toggle(self):
        self.enabled = not self.enabled if self.sounds else False


class Controls:
    # SDL scancodes track physical keys, independently of the OS input language.
    MAPS = (
        {pygame.KSCAN_A: "left", pygame.KSCAN_D: "right", pygame.KSCAN_S: "soft",
         pygame.KSCAN_W: "rotate", pygame.KSCAN_Q: "reverse", pygame.KSCAN_SPACE: "drop",
         pygame.KSCAN_LSHIFT: "hold"},
        {pygame.KSCAN_LEFT: "left", pygame.KSCAN_RIGHT: "right", pygame.KSCAN_DOWN: "soft",
         pygame.KSCAN_UP: "rotate", pygame.KSCAN_SLASH: "reverse", pygame.KSCAN_RETURN: "drop",
         pygame.KSCAN_KP_ENTER: "drop", pygame.KSCAN_RSHIFT: "hold"},
    )

    def __init__(self):
        self.clear()

    def clear(self):
        self.pressed = set()
        self.directions = [0, 0]
        self.repeat_timers = [0.0, 0.0]

    def keydown(self, scancode, match):
        if scancode in self.pressed:
            return
        self.pressed.add(scancode)
        for player, mapping in enumerate(self.MAPS):
            action = mapping.get(scancode)
            if action and action != "soft":
                match.action(player, action)
                if action in ("left", "right"):
                    self.directions[player] = -1 if action == "left" else 1
                    self.repeat_timers[player] = -0.16

    def keyup(self, scancode):
        self.pressed.discard(scancode)

    def tick(self, dt, match):
        soft = []
        for player, mapping in enumerate(self.MAPS):
            actions = {mapping[scan] for scan in self.pressed if scan in mapping}
            direction = int("right" in actions) - int("left" in actions)
            if direction != self.directions[player]:
                self.directions[player] = direction
                self.repeat_timers[player] = -0.16
                if direction:
                    match.action(player, "right" if direction > 0 else "left")
            elif direction:
                self.repeat_timers[player] += dt
                while self.repeat_timers[player] >= 0:
                    match.action(player, "right" if direction > 0 else "left")
                    self.repeat_timers[player] -= 0.045
            soft.append("soft" in actions)
        return tuple(soft)


class App:
    def __init__(self, args):
        self.args = args
        if args.headless:
            os.environ["SDL_VIDEODRIVER"] = "dummy"
            os.environ["SDL_AUDIODRIVER"] = "dummy"
        pygame.display.init()
        pygame.font.init()
        pygame.display.set_caption("TETRIS DUEL 3D — два игрока")
        info = pygame.display.Info()
        scale = min(1, max(0.5, (info.current_w-80)/SIZE[0]), max(0.5, (info.current_h-110)/SIZE[1]))
        self.window_size = SIZE if args.headless else (int(SIZE[0]*scale), int(SIZE[1]*scale))
        self.fullscreen = False
        self.display = pygame.display.set_mode(self.window_size, pygame.RESIZABLE)
        icon = pygame.Surface((32, 32), pygame.SRCALPHA)
        for x, y in ((1, 1), (16, 1), (16, 16)):
            pygame.draw.rect(icon, (91, 232, 196), (x, y, 13, 13), border_radius=3)
        pygame.display.set_icon(icon)
        pygame.key.set_repeat(0)
        self.clock = pygame.time.Clock()
        self.audio = Audio(args.mute or args.headless)
        self.renderer = Renderer()
        self.controls = Controls()
        self.rng = random.Random(args.seed)
        self.match = Match(self.rng.randrange(2**32))
        self.wins = [0, 0]
        self.phase = "menu"
        self.resume_phase = "playing"
        self.show_help = False
        self.countdown = 3.0
        self.running = True
        self.frames = 0
        if args.demo:
            self.make_demo()

    def make_demo(self):
        """A static, explicitly requested visual fixture for screenshots."""
        patterns = (
            ("JJ..L.....", "JJ..LLL...", "SS.TTT....", ".SZZT.OO..", "LLJZZ.OO..", "LJJJIIII.."),
            ("......T...", "OO...TTT..", "OOL..SS...", "LLL.SS.J..", "IIIIZ.ZJJJ", "SS.ZZZZLLL", ".SSZZZ.LLL"),
        )
        for player, pattern in enumerate(patterns):
            board = self.match.boards[player]
            for row, line in enumerate(pattern, HEIGHT-len(pattern)):
                board.grid[row] = [None if char == "." else char for char in line]
            board.piece.y = HIDDEN + 4 + player*2
            board.held = "T" if player == 0 else "I"
            board.score = 2480 if player == 0 else 1860
            board.lines = 12 if player == 0 else 9
            board.sent = 6 if player == 0 else 4
        self.match.elapsed = 84
        self.phase = "playing"

    def start(self):
        self.match = Match(self.rng.randrange(2**32))
        self.phase = "countdown"
        self.countdown = 3.0
        self.show_help = False
        self.controls.clear()
        self.renderer.particles.clear()
        self.renderer.notices = [None, None]
        self.renderer.flashes = [0.0, 0.0]

    def pause(self):
        if self.phase in ("playing", "countdown"):
            self.resume_phase = self.phase
            self.phase = "paused"
        elif self.phase == "paused":
            self.phase = self.resume_phase
        self.controls.clear()

    def toggle_fullscreen(self):
        if not self.fullscreen:
            self.window_size = self.display.get_size()
            self.display = pygame.display.set_mode((0, 0), pygame.FULLSCREEN)
        else:
            self.display = pygame.display.set_mode(self.window_size, pygame.RESIZABLE)
        self.fullscreen = not self.fullscreen

    def event(self, event):
        if event.type == pygame.QUIT:
            self.running = False
        elif event.type == pygame.WINDOWFOCUSLOST:
            self.controls.clear()
            if self.phase in ("playing", "countdown"):
                self.pause()
        elif event.type == pygame.KEYUP:
            self.controls.keyup(event.scancode)
        elif event.type == pygame.KEYDOWN:
            if getattr(event, "repeat", False):
                return
            scan = event.scancode
            if scan == pygame.KSCAN_F11:
                self.toggle_fullscreen()
            elif scan == pygame.KSCAN_M:
                self.audio.toggle()
            elif scan == pygame.KSCAN_V:
                self.renderer.camera_mode = 1 - self.renderer.camera_mode
            elif scan == pygame.KSCAN_F1:
                self.show_help = not self.show_help
                self.controls.clear()
            elif self.show_help:
                if scan == pygame.KSCAN_ESCAPE:
                    self.show_help = False
                    self.controls.clear()
            elif scan in (pygame.KSCAN_P, pygame.KSCAN_ESCAPE):
                if self.phase == "menu" and scan == pygame.KSCAN_ESCAPE:
                    self.running = False
                elif self.phase == "over" and scan == pygame.KSCAN_ESCAPE:
                    self.phase = "menu"
                else:
                    self.pause()
            elif scan == pygame.KSCAN_F2:
                self.start()
            elif self.phase in ("menu", "over") and scan in (pygame.KSCAN_RETURN, pygame.KSCAN_KP_ENTER):
                self.start()
            elif self.phase == "playing":
                self.controls.keydown(scan, self.match)

    def update(self, dt):
        if self.show_help or self.phase == "paused":
            return
        self.renderer.animate(dt)
        if self.phase == "countdown":
            self.countdown -= dt
            if self.countdown <= 0:
                self.phase = "playing"
                self.controls.clear()
                self.audio.play("start")
        elif self.phase == "playing":
            soft = self.controls.tick(dt, self.match)
            self.match.tick(dt, soft)
            for kind in set(self.renderer.consume_events(self.match)):
                self.audio.play(kind)
            if self.match.finished:
                self.phase = "over"
                if self.match.winner is not None:
                    self.wins[self.match.winner] += 1
                self.controls.clear()
                self.audio.play("over")

    def run(self):
        try:
            while self.running:
                dt = 1/60 if self.args.headless else min(self.clock.tick(60)/1000, 0.05)
                for event in pygame.event.get():
                    self.event(event)
                if not self.args.demo:
                    self.update(dt)
                self.renderer.draw(self, self.display)
                self.frames += 1
                if self.args.frames and self.frames >= self.args.frames:
                    self.running = False
            if self.args.screenshot:
                output = Path(self.args.screenshot)
                output.parent.mkdir(parents=True, exist_ok=True)
                pygame.image.save(self.renderer.surface, str(output))
                print(f"Screenshot: {output.resolve()}")
        finally:
            pygame.quit()


def main():
    parser = argparse.ArgumentParser(description="TETRIS DUEL 3D — два игрока на одной клавиатуре")
    parser.add_argument("--seed", type=int, default=None, help="Seed for reproducible matches")
    parser.add_argument("--mute", action="store_true", help="Start with sound disabled")
    parser.add_argument("--headless", action="store_true", help="Render with SDL's dummy driver")
    parser.add_argument("--frames", type=int, default=0, help="Exit after N frames (0 = unlimited)")
    parser.add_argument("--screenshot", type=str, help="Save the final frame as a PNG")
    parser.add_argument("--demo", action="store_true", help="Display a static demonstration fixture")
    args = parser.parse_args()
    if args.frames < 0:
        parser.error("--frames must be non-negative")
    if args.headless and not args.frames:
        args.frames = 1
    App(args).run()


if __name__ == "__main__":
    main()
