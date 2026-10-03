"""Small software 3D renderer and the game's Russian-language interface."""

from __future__ import annotations

from dataclasses import dataclass
import math
import random

import pygame

from engine import HEIGHT, HIDDEN, STATES, WIDTH

SIZE = (1440, 900)
BG = (11, 15, 23)
PANEL = (17, 23, 33)
LINE = (39, 49, 63)
TEXT = (230, 237, 244)
MUTED = (132, 149, 170)
ACCENTS = ((91, 232, 196), (255, 177, 105))
COLORS = {
    "I": (69, 208, 228), "J": (91, 135, 245), "L": (244, 163, 82),
    "O": (239, 206, 93), "S": (82, 205, 153), "T": (169, 131, 236),
    "Z": (240, 105, 130), "G": (99, 113, 135),
}


def shade(color, amount):
    return tuple(max(0, min(255, int(value * amount))) for value in color)


def blend(a, b, amount):
    return tuple(int(x + (y - x) * amount) for x, y in zip(a, b))


@dataclass
class Particle:
    x: float
    y: float
    vx: float
    vy: float
    life: float
    color: tuple
    size: float


class Camera:
    """Rotate 3D vertices, then project with a long focal length."""

    def __init__(self, cx, cy, scale, yaw=0.22, pitch=0.16):
        self.cx, self.cy, self.scale = cx, cy, scale
        self.sy, self.cyaw = math.sin(yaw), math.cos(yaw)
        self.sp, self.cp = math.sin(pitch), math.cos(pitch)

    def transform(self, point):
        x, y, z = point
        rx = self.cyaw * x + self.sy * z
        rz = -self.sy * x + self.cyaw * z
        return rx, self.cp * y - self.sp * rz, self.sp * y + self.cp * rz

    def project(self, point):
        x, y, z = self.transform(point)
        perspective = 85 / (85 - z)
        return (self.cx + x * self.scale * perspective,
                self.cy - y * self.scale * perspective)

    def cube_faces(self, x, y, z, w, h, d, color, active=False):
        vertices = ((x, y, z), (x+w, y, z), (x+w, y+h, z), (x, y+h, z),
                    (x, y, z+d), (x+w, y, z+d), (x+w, y+h, z+d), (x, y+h, z+d))
        faces = (((4, 5, 6, 7), (0, 0, 1), 1.0),
                 ((3, 7, 6, 2), (0, 1, 0), 1.24),
                 ((0, 4, 7, 3), (-1, 0, 0), 0.62),
                 ((1, 2, 6, 5), (1, 0, 0), 0.76))
        result = []
        for indices, normal, light in faces:
            if self.transform(normal)[2] <= 0:
                continue
            points = [vertices[index] for index in indices]
            depth = sum(self.transform(point)[2] for point in points) / 4
            face_color = shade(color, light)
            edge = blend(face_color, (255, 255, 255), 0.33 if active else 0.13)
            result.append((depth, [self.project(point) for point in points], face_color, edge))
        return result


class Renderer:
    def __init__(self):
        self.surface = pygame.Surface(SIZE)
        self.fonts = {}
        self.particles: list[Particle] = []
        self.rng = random.Random(77)
        self.notices = [None, None]
        self.flashes = [0.0, 0.0]
        self.camera_mode = 0
        self.background = self.make_background()
        self.last_viewport = pygame.Rect(0, 0, *SIZE)

    def font(self, size, bold=False):
        key = (size, bold)
        if key not in self.fonts:
            self.fonts[key] = pygame.font.SysFont("segoeui,dejavusans,arial", size, bold=bold)
        return self.fonts[key]

    def text(self, value, x, y, size=18, color=TEXT, bold=False, anchor="topleft"):
        label = self.font(size, bold).render(str(value), True, color)
        rect = label.get_rect(**{anchor: (round(x), round(y))})
        self.surface.blit(label, rect)
        return rect

    def rect(self, bounds, fill=PANEL, border=LINE, radius=14):
        pygame.draw.rect(self.surface, fill, bounds, border_radius=radius)
        if border:
            pygame.draw.rect(self.surface, border, bounds, 1, border_radius=radius)

    def make_background(self):
        background = pygame.Surface(SIZE)
        for y in range(SIZE[1]):
            color = blend((17, 24, 35), BG, min(1, y / 650))
            pygame.draw.line(background, color, (0, y), (SIZE[0], y))
        for x in range(0, SIZE[0], 48):
            pygame.draw.line(background, (21, 28, 38), (x, 0), (x, 138))
        for y in range(0, 140, 48):
            pygame.draw.line(background, (21, 28, 38), (0, y), (SIZE[0], y))
        return background

    def camera(self, player, small=False):
        card_x = 34 if player == 0 else 774
        yaw = (0.22 if player == 0 else -0.22) if not self.camera_mode else 0.0
        pitch = 0.16 if not self.camera_mode else 0.07
        return Camera(card_x + 408, 493, 25.5, yaw, pitch)

    def draw_faces(self, faces):
        for _, points, color, edge in sorted(faces, key=lambda face: face[0]):
            pygame.draw.polygon(self.surface, color, points)
            pygame.draw.aalines(self.surface, edge, True, points)

    def mini_piece(self, kind, cx, cy, scale=20, muted=False):
        if not kind:
            self.text("—", cx, cy, 30, MUTED, anchor="center")
            return
        cells = STATES[kind][0]
        min_x, max_x = min(x for x, _ in cells), max(x for x, _ in cells)
        min_y, max_y = min(y for _, y in cells), max(y for _, y in cells)
        camera = Camera(cx, cy, scale, 0.24, 0.24)
        faces = []
        color = shade(COLORS[kind], 0.48) if muted else COLORS[kind]
        for x, y in cells:
            faces += camera.cube_faces(x - (min_x+max_x+1)/2 + 0.04,
                                       (min_y+max_y+1)/2 - y - 0.96, 0,
                                       0.92, 0.92, 0.7, color)
        self.draw_faces(faces)

    def keycap(self, label, x, y, width=None, accent=MUTED):
        width = width or max(27, self.font(13, True).size(label)[0] + 14)
        self.rect((x, y, width, 25), (26, 34, 46), (54, 67, 83), 5)
        self.text(label, x + width/2, y + 12, 13, accent, True, "center")
        return width

    def controls(self, player, x, y):
        accent = ACCENTS[player]
        row1 = (("A D", "двигать"), ("W / Q", "поворот"), ("S", "вниз")) if player == 0 else (
            ("← →", "двигать"), ("↑  /", "поворот"), ("↓", "вниз"))
        pos = x
        for key, label in row1:
            width = self.keycap(key, pos, y, accent=accent)
            self.text(label, pos + width + 7, y + 3, 14, MUTED)
            pos += width + 7 + self.font(14).size(label)[0] + 20
        row2 = (("SPACE", "сбросить"), ("L SHIFT", "запас")) if player == 0 else (
            ("ENTER", "сбросить"), ("R SHIFT", "запас"))
        pos = x
        for key, label in row2:
            width = self.keycap(key, pos, y + 33, accent=accent)
            self.text(label, pos + width + 7, y + 36, 14, MUTED)
            pos += width + 7 + self.font(14).size(label)[0] + 26

    def board(self, board, player, wins):
        x = 34 if player == 0 else 774
        accent = ACCENTS[player]
        self.rect((x, 159, 632, 656))
        pygame.draw.line(self.surface, accent, (x+19, 160), (x+107, 160), 2)
        self.rect((x+20, 180, 34, 34), shade(accent, 0.17), None, 9)
        self.text(f"0{player+1}", x+37, 197, 16, accent, True, "center")
        self.text(f"ИГРОК {player+1}", x+66, 181, 23, TEXT, True)
        self.text("БИРЮЗОВЫЙ" if player == 0 else "ЯНТАРНЫЙ", x+67, 210, 10, MUTED, True)
        self.text(f"ПОБЕДЫ  {wins}", x+607, 197, 13, MUTED, anchor="midright")
        pygame.draw.line(self.surface, LINE, (x+20, 236), (x+612, 236))

        sx = x + 24
        self.text("СЧЁТ", sx, 257, 12, MUTED, True)
        self.text(f"{board.score:,}".replace(",", " "), sx, 275, 34, TEXT, True)
        self.text("ЛИНИИ", sx, 329, 11, MUTED, True)
        self.text(f"{board.lines:02}", sx, 345, 23, TEXT, True)
        self.text("УРОВЕНЬ", sx+91, 329, 11, MUTED, True)
        self.text(f"{board.level:02}", sx+91, 345, 23, TEXT, True)

        self.rect((sx, 393, 156, 101), (13, 19, 28), LINE, 10)
        self.text("ЗАПАС", sx+12, 403, 11, MUTED, True)
        if board.hold_used:
            self.text("•", sx+137, 401, 14, accent)
        self.mini_piece(board.held, sx+78, 457, 22, board.hold_used)
        self.rect((sx, 508, 156, 220), (13, 19, 28), LINE, 10)
        self.text("ДАЛЬШЕ", sx+12, 519, 11, MUTED, True)
        for index, kind in enumerate(board.preview()):
            self.mini_piece(kind, sx+77, 568+index*60, 21 if index == 0 else 18)
            if index != 2:
                pygame.draw.line(self.surface, (28, 36, 49), (sx+18, 598+index*60),
                                 (sx+138, 598+index*60))
        self.text("АТАКА", sx, 750, 11, MUTED, True)
        self.text(f"{board.sent:02}", sx, 767, 23, accent, True)
        self.text("строк", sx+42, 777, 12, MUTED)

        camera = self.camera(player)
        back = [camera.project(p) for p in ((-5.18, -10.16, -0.18), (5.18, -10.16, -0.18),
                                            (5.18, 10.16, -0.18), (-5.18, 10.16, -0.18))]
        pygame.draw.polygon(self.surface, (8, 13, 21), back)
        pygame.draw.aalines(self.surface, (51, 66, 85), True, back)
        for column in range(WIDTH+1):
            pygame.draw.aaline(self.surface, (24, 34, 47),
                               camera.project((column-5, -10, -0.1)),
                               camera.project((column-5, 10, -0.1)))
        for row in range(21):
            pygame.draw.aaline(self.surface, (24, 34, 47),
                               camera.project((-5, row-10, -0.1)),
                               camera.project((5, row-10, -0.1)))

        if board.alive:
            ghost = board.piece.cells(dy=board.ghost_distance())
            for gx, gy in ghost:
                if gy < HIDDEN:
                    continue
                bottom = 10 - (gy-HIDDEN) - 1
                points = [camera.project(p) for p in ((gx-4.94, bottom+0.06, 0.85),
                          (gx-4.06, bottom+0.06, 0.85), (gx-4.06, bottom+0.94, 0.85),
                          (gx-4.94, bottom+0.94, 0.85))]
                pygame.draw.polygon(self.surface, blend((8, 13, 21), COLORS[board.piece.kind], 0.1), points)
                pygame.draw.aalines(self.surface, shade(COLORS[board.piece.kind], 0.50), True, points)

        faces = []
        for row in range(HIDDEN, HEIGHT):
            for column, kind in enumerate(board.grid[row]):
                if kind:
                    faces += camera.cube_faces(column-4.96, 10-(row-HIDDEN)-0.96, 0,
                                               0.92, 0.92, 0.86, COLORS[kind])
        if board.alive:
            for px, py in board.piece.cells():
                if py >= HIDDEN:
                    faces += camera.cube_faces(px-4.96, 10-(py-HIDDEN)-0.96, 0,
                                               0.92, 0.92, 0.86, COLORS[board.piece.kind], True)
        self.draw_faces(faces)
        rails = camera.cube_faces(-5.2, -10.35, -0.18, 10.4, 0.20, 1.18, shade(accent, 0.4))
        self.draw_faces(rails)

        if self.flashes[player] > 0:
            strength = self.flashes[player] / 0.3
            pygame.draw.aalines(self.surface, shade(accent, strength), True, back)
        # The separate meter is visible even when garbage is not ready to rise.
        meter_x = x+602
        self.rect((meter_x, 272, 8, 443), (30, 39, 52), None, 4)
        if board.incoming:
            fill_height = min(443, board.incoming * 22)
            self.rect((meter_x, 715-fill_height, 8, fill_height), (245, 112, 120), None, 4)
            self.text(f"+{board.incoming}", meter_x+4, 734, 15, (245, 112, 120), True, "center")
        if self.notices[player]:
            label, remaining = self.notices[player]
            color = blend(PANEL, accent, min(1, remaining*2))
            self.text(label, x+408, 777, 15, color, True, "center")
        else:
            self.text("10 × 20  /  3D", x+408, 777, 11, MUTED, anchor="center")

    def consume_events(self, match):
        kinds = []
        for player, board in enumerate(match.boards):
            camera = self.camera(player)
            for event in board.events:
                kinds.append(event.kind)
                if event.kind == "clear":
                    self.flashes[player] = 0.3
                    title = "ЧИСТОЕ ПОЛЕ!" if event.perfect else ("ТЕТРИС!" if event.lines == 4 else f"ЛИНИИ ×{event.lines}")
                    if event.attack:
                        title += f"  /  АТАКА +{event.attack}"
                    self.notices[player] = (title, 2.0)
                elif event.kind == "garbage":
                    self.notices[player] = (f"АТАКА СОПЕРНИКА +{event.lines}", 1.8)
                if event.kind in ("clear", "lock"):
                    for x, y in event.cells:
                        if y < HIDDEN:
                            continue
                        px, py = camera.project((x-4.5, 9.5-(y-HIDDEN), 0.85))
                        for _ in range(3 if event.kind == "clear" else 2):
                            self.particles.append(Particle(px, py, self.rng.uniform(-100, 100),
                                                  self.rng.uniform(-100, 30), self.rng.uniform(0.2, 0.65),
                                                  COLORS[event.piece], self.rng.uniform(1.5, 3.5)))
            board.events.clear()
        self.particles = self.particles[-650:]
        return kinds

    def animate(self, dt):
        for particle in self.particles:
            particle.life -= dt
            particle.x += particle.vx * dt
            particle.y += particle.vy * dt
            particle.vy += 160 * dt
        self.particles = [p for p in self.particles if p.life > 0]
        self.flashes = [max(0, value-dt) for value in self.flashes]
        for player, notice in enumerate(self.notices):
            if notice:
                label, remaining = notice
                self.notices[player] = (label, remaining-dt) if remaining > dt else None

    def overlay(self, app):
        veil = pygame.Surface(SIZE, pygame.SRCALPHA)
        veil.fill((4, 8, 15, 210 if app.phase == "menu" else 192))
        self.surface.blit(veil, (0, 0))
        if app.phase == "countdown":
            count = max(1, math.ceil(app.countdown))
            self.text("ПРИГОТОВЬТЕСЬ", 720, 339, 17, ACCENTS[0], True, "center")
            self.text(str(count), 720, 467, 150, TEXT, True, "center")
            self.text("Одна клавиатура. Два игрока.", 720, 590, 20, MUTED, anchor="center")
            return
        if app.phase == "menu":
            self.rect((390, 238, 660, 416), (18, 25, 37), (60, 77, 97), 22)
            self.text("ЛОКАЛЬНЫЙ МУЛЬТИПЛЕЕР", 720, 277, 13, ACCENTS[0], True, "center")
            self.text("ДВА ИГРОКА.", 720, 335, 45, TEXT, True, "center")
            self.text("ОДИН ПОБЕДИТЕЛЬ.", 720, 393, 45, TEXT, True, "center")
            self.text("Собирайте линии. Отправляйте атаки.", 720, 455, 20, MUTED, anchor="center")
            self.text("Выигрывает тот, кто продержится дольше.", 720, 485, 19, MUTED, anchor="center")
            self.rect((496, 537, 448, 60), ACCENTS[0], None, 11)
            self.text("ENTER   /   НАЧАТЬ ДУЭЛЬ", 720, 567, 20, BG, True, "center")
            self.text("Одинаковые фигуры • Атаки за 2 / 3 / 4 линии", 720, 626, 14, MUTED, anchor="center")
        elif app.phase == "paused":
            self.rect((430, 291, 580, 296), (18, 25, 37), (60, 77, 97), 22)
            self.text("ПАУЗА", 720, 357, 49, TEXT, True, "center")
            self.text("P или ESC — продолжить", 720, 430, 22, ACCENTS[0], anchor="center")
            self.text("F2 — новая дуэль    •    F1 — управление", 720, 478, 17, MUTED, anchor="center")
            self.text("Таймер и оба поля остановлены", 720, 539, 14, MUTED, anchor="center")
        elif app.phase == "over":
            winner = app.match.winner
            accent = ACCENTS[winner] if winner is not None else TEXT
            self.rect((410, 272, 620, 350), (18, 25, 37), shade(accent, 0.5), 22)
            self.text("ДУЭЛЬ ЗАВЕРШЕНА", 720, 312, 13, MUTED, True, "center")
            self.text("НИЧЬЯ" if winner is None else f"ИГРОК {winner+1} ПОБЕДИЛ", 720, 376,
                      39, accent, True, "center")
            self.text(f"СЧЁТ МАТЧЕЙ    {app.wins[0]} : {app.wins[1]}", 720, 439, 22, TEXT, True, "center")
            self.text("Оба поля заполнены одновременно" if winner is None else "Соперник заполнил своё поле",
                      720, 478, 16, MUTED, anchor="center")
            self.rect((501, 525, 438, 57), accent, None, 10)
            self.text("ENTER   /   РЕВАНШ", 720, 553, 20, BG, True, "center")

    def help_overlay(self):
        veil = pygame.Surface(SIZE, pygame.SRCALPHA)
        veil.fill((4, 8, 15, 236))
        self.surface.blit(veil, (0, 0))
        self.rect((260, 167, 920, 570), (18, 25, 37), (60, 77, 97), 22)
        self.text("КАК ИГРАТЬ", 720, 210, 33, TEXT, True, "center")
        self.text("ИГРОК 1", 304, 282, 21, ACCENTS[0], True)
        self.text("ИГРОК 2", 751, 282, 21, ACCENTS[1], True)
        self.controls(0, 304, 329)
        self.controls(1, 751, 329)
        lines = ["Заполняйте горизонтальные линии без пробелов.",
                 "2 / 3 / 4 линии отправляют сопернику 1 / 2 / 4 строки.",
                 "Комбо усиливает атаку. Свои линии погашают входящую атаку.",
                 "Запас — один раз на фигуру. Контур показывает место приземления.",
                 "Кто заполнит поле до верха, проиграет. Очки не решают исход."]
        for index, line in enumerate(lines):
            self.text(line, 304, 432+index*34, 18, MUTED)
        self.text("P / ESC  пауза     V  ракурс     M  звук     F11  полный экран", 720, 648,
                  16, TEXT, anchor="center")
        self.text("F1 или ESC — закрыть", 720, 699, 17, ACCENTS[0], True, "center")

    def draw(self, app, display):
        self.surface.blit(self.background, (0, 0))
        # Geometric mark, matching the cubes on the two boards.
        for ox, oy in ((0, 0), (19, 0), (19, 19), (38, 19)):
            self.rect((35+ox, 43+oy, 16, 16), ACCENTS[0], None, 3)
        self.text("TETRIS", 110, 25, 48, TEXT, True)
        self.text("DUEL", 282, 25, 48, ACCENTS[0], True)
        self.rect((424, 44, 47, 27), (33, 45, 57), None, 6)
        self.text("3D", 448, 58, 14, TEXT, True, "center")
        self.text("ДВА ИГРОКА  /  ОДНА КЛАВИАТУРА", 36, 105, 13, MUTED, True)
        status = {"menu": "ГОТОВЫ К ДУЭЛИ", "countdown": "ПРИГОТОВЬТЕСЬ", "playing": "МАТЧ ИДЁТ",
                  "paused": "ПАУЗА", "over": "МАТЧ ЗАВЕРШЁН"}[app.phase]
        self.text(status, 1404, 41, 13, ACCENTS[0], True, "topright")
        self.text("F1  помощь     M  звук " + ("ВКЛ" if app.audio.enabled else "ВЫКЛ"),
                  1404, 78, 14, MUTED, anchor="topright")
        pygame.draw.line(self.surface, LINE, (34, 137), (1406, 137))
        self.board(app.match.boards[0], 0, app.wins[0])
        self.board(app.match.boards[1], 1, app.wins[1])
        self.rect((687, 181, 66, 40), (26, 35, 48), LINE, 10)
        self.text("VS", 720, 201, 17, TEXT, True, "center")
        seconds = int(app.match.elapsed)
        self.text(f"{seconds//60:02}:{seconds%60:02}", 720, 273, 18, TEXT, True, "center")
        self.text("ВРЕМЯ", 720, 298, 9, MUTED, True, "center")
        self.text(f"{app.wins[0]} : {app.wins[1]}", 720, 414, 21, TEXT, True, "center")
        self.text("МАТЧИ", 720, 443, 9, MUTED, True, "center")
        for particle in self.particles:
            color = shade(particle.color, min(1, particle.life*4))
            pygame.draw.circle(self.surface, color, (particle.x, particle.y), particle.size)
        self.controls(0, 58, 827)
        self.controls(1, 798, 827)
        self.text("P  пауза", 720, 839, 11, MUTED, anchor="center")
        self.text("V  ракурс", 720, 869, 11, MUTED, anchor="center")
        if app.phase != "playing":
            self.overlay(app)
        if app.show_help:
            self.help_overlay()
        width, height = display.get_size()
        scale = min(width / SIZE[0], height / SIZE[1])
        output_size = (max(1, round(SIZE[0]*scale)), max(1, round(SIZE[1]*scale)))
        self.last_viewport = pygame.Rect((width-output_size[0])//2, (height-output_size[1])//2, *output_size)
        display.fill(BG)
        if output_size == SIZE:
            display.blit(self.surface, self.last_viewport)
        else:
            pygame.transform.smoothscale(self.surface, output_size, display.subsurface(self.last_viewport))
        pygame.display.flip()
