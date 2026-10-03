"""Deterministic two-player Tetris rules, independent of graphics and input."""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass
import random

WIDTH = 10
HEIGHT = 22
HIDDEN = 2
LOCK_DELAY = 0.5
MAX_LOCK_RESETS = 15

SHAPES = {
    "I": ("....", "IIII", "....", "...."),
    "J": ("J..", "JJJ", "..."),
    "L": ("..L", "LLL", "..."),
    "O": (".OO.", ".OO.", "....", "...."),
    "S": (".SS", "SS.", "..."),
    "T": (".T.", "TTT", "..."),
    "Z": ("ZZ.", ".ZZ", "..."),
}


def shape_states(kind: str) -> tuple[tuple[tuple[int, int], ...], ...]:
    matrix = SHAPES[kind]
    states = []
    for _ in range(4):
        states.append(tuple((x, y) for y, row in enumerate(matrix)
                            for x, value in enumerate(row) if value != "."))
        if kind != "O":
            matrix = tuple("".join(row) for row in zip(*matrix[::-1]))
    return tuple(states)


STATES = {kind: shape_states(kind) for kind in SHAPES}

# SRS wall kicks; y is positive downwards in this implementation.
KICKS = {
    (0, 1): ((0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)),
    (1, 0): ((0, 0), (1, 0), (1, 1), (0, -2), (1, -2)),
    (1, 2): ((0, 0), (1, 0), (1, 1), (0, -2), (1, -2)),
    (2, 1): ((0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)),
    (2, 3): ((0, 0), (1, 0), (1, -1), (0, 2), (1, 2)),
    (3, 2): ((0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)),
    (3, 0): ((0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)),
    (0, 3): ((0, 0), (1, 0), (1, -1), (0, 2), (1, 2)),
}
I_KICKS = {
    (0, 1): ((0, 0), (-2, 0), (1, 0), (-2, 1), (1, -2)),
    (1, 0): ((0, 0), (2, 0), (-1, 0), (2, -1), (-1, 2)),
    (1, 2): ((0, 0), (-1, 0), (2, 0), (-1, -2), (2, 1)),
    (2, 1): ((0, 0), (1, 0), (-2, 0), (1, 2), (-2, -1)),
    (2, 3): ((0, 0), (2, 0), (-1, 0), (2, -1), (-1, 2)),
    (3, 2): ((0, 0), (-2, 0), (1, 0), (-2, 1), (1, -2)),
    (3, 0): ((0, 0), (1, 0), (-2, 0), (1, 2), (-2, -1)),
    (0, 3): ((0, 0), (-1, 0), (2, 0), (-1, -2), (2, 1)),
}


class PieceStream:
    """One shared seven-bag sequence; each player has an independent cursor."""

    def __init__(self, seed: int):
        self.rng = random.Random(seed)
        self.pieces: list[str] = []

    def at(self, index: int) -> str:
        while len(self.pieces) <= index:
            bag = list(SHAPES)
            self.rng.shuffle(bag)
            self.pieces.extend(bag)
        return self.pieces[index]


@dataclass
class Piece:
    kind: str
    x: int = 3
    y: int = 0
    rotation: int = 0

    def cells(self, dx: int = 0, dy: int = 0, rotation: int | None = None):
        state = self.rotation if rotation is None else rotation
        return tuple((self.x + x + dx, self.y + y + dy)
                     for x, y in STATES[self.kind][state])


@dataclass
class Garbage:
    rows: int
    hole: int
    ready_at: float


@dataclass
class GameEvent:
    kind: str
    cells: tuple[tuple[int, int], ...] = ()
    piece: str = "I"
    lines: int = 0
    attack: int = 0
    perfect: bool = False


class Board:
    def __init__(self, stream: PieceStream):
        self.stream = stream
        self.cursor = 0
        self.grid: list[list[str | None]] = [[None] * WIDTH for _ in range(HEIGHT)]
        self.piece: Piece | None = None
        self.held: str | None = None
        self.hold_used = False
        self.alive = True
        self.score = 0
        self.lines = 0
        self.pieces_placed = 0
        self.sent = 0
        self.combo = -1
        self.back_to_back = False
        self.pending: deque[Garbage] = deque()
        self.outgoing = 0
        self.gravity_time = 0.0
        self.lock_time = 0.0
        self.lock_resets = 0
        self.now = 0.0
        self.events: list[GameEvent] = []
        self.spawn()

    @property
    def level(self) -> int:
        return 1 + self.lines // 10

    @property
    def gravity_interval(self) -> float:
        return max(0.07, 0.8 * 0.82 ** (self.level - 1))

    @property
    def incoming(self) -> int:
        return sum(packet.rows for packet in self.pending)

    def preview(self, count: int = 3) -> list[str]:
        return [self.stream.at(self.cursor + index) for index in range(count)]

    def spawn(self, kind: str | None = None):
        if kind is None:
            kind = self.stream.at(self.cursor)
            self.cursor += 1
        self.piece = Piece(kind)
        self.gravity_time = self.lock_time = 0.0
        self.lock_resets = 0
        if not self.valid():
            self.alive = False

    def valid(self, dx: int = 0, dy: int = 0, rotation: int | None = None) -> bool:
        if self.piece is None:
            return False
        return all(0 <= x < WIDTH and 0 <= y < HEIGHT and self.grid[y][x] is None
                   for x, y in self.piece.cells(dx, dy, rotation))

    def grounded(self) -> bool:
        return not self.valid(dy=1)

    def reset_lock(self, was_grounded: bool):
        if was_grounded and self.lock_resets < MAX_LOCK_RESETS:
            self.lock_time = 0.0
            self.lock_resets += 1

    def move(self, dx: int) -> bool:
        if not self.alive or not self.valid(dx=dx):
            return False
        was_grounded = self.grounded()
        self.piece.x += dx
        self.reset_lock(was_grounded)
        return True

    def rotate(self, direction: int = 1) -> bool:
        if not self.alive or self.piece.kind == "O":
            return False
        old_rotation = self.piece.rotation
        new_rotation = (old_rotation + direction) % 4
        kicks = I_KICKS if self.piece.kind == "I" else KICKS
        was_grounded = self.grounded()
        for dx, dy in kicks[old_rotation, new_rotation]:
            if self.valid(dx, dy, new_rotation):
                self.piece.x += dx
                self.piece.y += dy
                self.piece.rotation = new_rotation
                self.reset_lock(was_grounded)
                return True
        return False

    def hold(self) -> bool:
        if not self.alive or self.hold_used:
            return False
        kind = self.piece.kind
        replacement = self.held
        self.held = kind
        self.spawn(replacement)
        self.hold_used = True
        self.events.append(GameEvent("hold", piece=kind))
        return True

    def ghost_distance(self) -> int:
        distance = 0
        while self.valid(dy=distance + 1):
            distance += 1
        return distance

    def hard_drop(self):
        if not self.alive:
            return
        distance = self.ghost_distance()
        self.score += 2 * distance
        self.piece.y += distance
        self.lock()

    def cancel_incoming(self, attack: int) -> int:
        while attack and self.pending:
            packet = self.pending[0]
            cancelled = min(attack, packet.rows)
            attack -= cancelled
            packet.rows -= cancelled
            if packet.rows == 0:
                self.pending.popleft()
        return attack

    def apply_garbage(self):
        # Garbage arrives between pieces, with a warning and an eight-row cap.
        budget = 8
        applied = 0
        while self.pending and self.pending[0].ready_at <= self.now and budget:
            packet = self.pending[0]
            count = min(packet.rows, budget)
            if any(any(row) for row in self.grid[:count]):
                self.alive = False
            del self.grid[:count]
            self.grid.extend([[None if x == packet.hole else "G" for x in range(WIDTH)]
                              for _ in range(count)])
            packet.rows -= count
            budget -= count
            applied += count
            if not packet.rows:
                self.pending.popleft()
        if applied:
            self.events.append(GameEvent("garbage", lines=applied))

    def lock(self):
        cells = self.piece.cells()
        kind = self.piece.kind
        for x, y in cells:
            self.grid[y][x] = kind
        self.pieces_placed += 1
        full_rows = [y for y, row in enumerate(self.grid) if all(row)]
        count = len(full_rows)
        attack = 0
        perfect = False
        if count:
            level = self.level
            clear_cells = tuple((x, y) for y in full_rows for x in range(WIDTH))
            self.grid = [[None] * WIDTH for _ in full_rows] + [
                row for y, row in enumerate(self.grid) if y not in full_rows]
            self.combo += 1
            bonus = self.back_to_back and count == 4
            points = (0, 100, 300, 500, 800)[count]
            if bonus:
                points = points * 3 // 2
            self.score += (points + 50 * max(0, self.combo)) * level
            self.lines += count
            self.back_to_back = count == 4
            attack = (0, 0, 1, 2, 4)[count] + int(bonus) + min(4, self.combo // 2)
            perfect = not any(any(row) for row in self.grid)
            if perfect:
                self.score += 2000 * level
                attack += 6
            attack = self.cancel_incoming(attack)
            self.outgoing += attack
            self.sent += attack
            self.events.append(GameEvent("clear", clear_cells, kind, count, attack, perfect))
        else:
            self.combo = -1
            self.events.append(GameEvent("lock", cells, kind))
            self.apply_garbage()
        if all(y < HIDDEN for _, y in cells) and not count:
            self.alive = False
        self.hold_used = False
        if self.alive:
            self.spawn()

    def tick(self, dt: float, soft_drop: bool = False):
        if not self.alive:
            return
        interval = min(self.gravity_interval, 0.035) if soft_drop else self.gravity_interval
        self.gravity_time += dt
        while self.gravity_time >= interval:
            self.gravity_time -= interval
            if self.valid(dy=1):
                self.piece.y += 1
                if soft_drop:
                    self.score += 1
            else:
                self.gravity_time = 0.0
                break
        if self.grounded():
            self.lock_time += dt
            if self.lock_time >= LOCK_DELAY:
                self.lock()
        elif self.lock_resets < MAX_LOCK_RESETS:
            self.lock_time = 0.0


class Match:
    def __init__(self, seed: int):
        self.seed = seed
        self.stream = PieceStream(seed)
        self.boards = [Board(self.stream), Board(self.stream)]
        # Matching per-attacker streams keep garbage holes symmetric.
        self.garbage_rng = [random.Random(seed ^ 0xD0E1), random.Random(seed ^ 0xD0E1)]
        self.elapsed = 0.0
        self.finished = False
        self.winner: int | None = None

    def action(self, player: int, action: str):
        if self.finished:
            return
        board = self.boards[player]
        if action == "left":
            board.move(-1)
        elif action == "right":
            board.move(1)
        elif action == "rotate":
            board.rotate(1)
        elif action == "reverse":
            board.rotate(-1)
        elif action == "drop":
            board.hard_drop()
        elif action == "hold":
            board.hold()

    def tick(self, dt: float, soft_drop: tuple[bool, bool] = (False, False)):
        if self.finished:
            return
        self.elapsed += dt
        for board, soft in zip(self.boards, soft_drop):
            board.now = self.elapsed
            board.tick(dt, soft)
        # Deliver only after both boards advance: no advantage to player order.
        attacks = [board.outgoing for board in self.boards]
        mutual = min(attacks)
        for player, attack in enumerate(attacks):
            attack -= mutual
            self.boards[player].outgoing = 0
            if attack:
                opponent = self.boards[1 - player]
                opponent.pending.append(Garbage(attack, self.garbage_rng[player].randrange(WIDTH),
                                                self.elapsed + 1.5))
        alive = [board.alive for board in self.boards]
        if not all(alive):
            self.finished = True
            self.winner = None if not any(alive) else alive.index(True)
