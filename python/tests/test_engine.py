import random
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from engine import Board, Garbage, HEIGHT, HIDDEN, Match, Piece, PieceStream, SHAPES, WIDTH


class EngineTests(unittest.TestCase):
    def board(self):
        return Board(PieceStream(42))

    def tetris_well(self, board):
        for row in range(HEIGHT-4, HEIGHT):
            board.grid[row] = ["J"] * WIDTH
            board.grid[row][4] = None
        # A survivor prevents the separate perfect-clear bonus.
        board.grid[HEIGHT-5][0] = "T"
        board.piece = Piece("I", x=2, y=0, rotation=1)

    def test_seven_bag_and_reproducibility(self):
        first, second = PieceStream(913), PieceStream(913)
        for offset in range(0, 140, 7):
            bag = [first.at(offset+i) for i in range(7)]
            self.assertEqual(set(bag), set(SHAPES))
            self.assertEqual(bag, [second.at(offset+i) for i in range(7)])

    def test_players_share_sequence_at_different_speeds(self):
        match = Match(126)
        left, right = match.boards
        observed = [left.piece.kind]
        for _ in range(28):
            left.grid = [[None]*WIDTH for _ in range(HEIGHT)]
            left.hard_drop()
            observed.append(left.piece.kind)
        for kind in observed:
            self.assertEqual(right.piece.kind, kind)
            right.grid = [[None]*WIDTH for _ in range(HEIGHT)]
            right.hard_drop()

    def test_horizontal_collision_and_ghost(self):
        board = self.board()
        board.piece = Piece("O", y=4)
        while board.move(-1):
            pass
        self.assertEqual(min(x for x, _ in board.piece.cells()), 0)
        self.assertTrue(board.valid(dy=board.ghost_distance()))
        self.assertFalse(board.valid(dy=board.ghost_distance()+1))
        while board.move(1):
            pass
        self.assertEqual(max(x for x, _ in board.piece.cells()), WIDTH-1)

    def test_rotation_round_trip_and_floor_kick(self):
        board = self.board()
        board.piece = Piece("T", x=3, y=5)
        original = board.piece.cells()
        for _ in range(4):
            self.assertTrue(board.rotate())
        self.assertEqual(board.piece.cells(), original)
        board.piece = Piece("T", x=3, y=20)
        self.assertTrue(board.valid())
        self.assertTrue(board.rotate())
        self.assertTrue(board.valid())
        self.assertLess(board.piece.y, 20)

    def test_i_wall_kick(self):
        board = self.board()
        board.piece = Piece("I", x=-2, y=5, rotation=1)
        self.assertTrue(board.valid())
        self.assertTrue(board.rotate(-1))
        self.assertTrue(board.valid())
        self.assertGreaterEqual(min(x for x, _ in board.piece.cells()), 0)

    def test_hold_once_and_swap_resets_orientation(self):
        board = self.board()
        original = board.piece.kind
        next_kind = board.preview()[0]
        self.assertTrue(board.hold())
        self.assertEqual(board.held, original)
        self.assertEqual(board.piece.kind, next_kind)
        self.assertFalse(board.hold())
        board.hard_drop()
        cursor = board.cursor
        self.assertTrue(board.hold())
        self.assertEqual(board.piece.kind, original)
        self.assertEqual(board.piece.rotation, 0)
        self.assertEqual(board.cursor, cursor)

    def test_hard_drop_locks_immediately_and_scores_distance(self):
        board = self.board()
        distance = board.ghost_distance()
        board.hard_drop()
        self.assertEqual(board.pieces_placed, 1)
        self.assertEqual(board.score, distance*2)
        self.assertEqual(sum(bool(cell) for row in board.grid for cell in row), 4)

    def test_four_lines_clear_score_and_attack(self):
        board = self.board()
        self.tetris_well(board)
        drop_points = board.ghost_distance()*2
        board.hard_drop()
        self.assertEqual(board.lines, 4)
        self.assertEqual(board.score, 800+drop_points)
        self.assertEqual(board.outgoing, 4)
        self.assertEqual(board.grid[-1][0], "T")
        self.assertEqual(sum(bool(cell) for row in board.grid for cell in row), 1)

    def test_single_line_does_not_attack(self):
        board = self.board()
        board.grid[-1] = ["J"]*WIDTH
        for column in (3, 4, 5, 6):
            board.grid[-1][column] = None
        board.grid[-2][0] = "J"
        board.piece = Piece("I", x=3)
        board.hard_drop()
        self.assertEqual(board.lines, 1)
        self.assertEqual(board.outgoing, 0)

    def test_perfect_clear_bonus(self):
        board = self.board()
        self.tetris_well(board)
        board.grid[HEIGHT-5][0] = None
        board.hard_drop()
        self.assertEqual(board.outgoing, 10)
        self.assertTrue(board.events[-1].perfect)
        self.assertFalse(any(any(row) for row in board.grid))

    def test_back_to_back_and_combo(self):
        board = self.board()
        self.tetris_well(board)
        board.hard_drop()
        board.outgoing = 0
        board.grid = [[None]*WIDTH for _ in range(HEIGHT)]
        self.tetris_well(board)
        score_before = board.score
        drop_points = board.ghost_distance()*2
        board.hard_drop()
        self.assertEqual(board.outgoing, 5)
        self.assertEqual(board.score-score_before, 1200+50+drop_points)

    def test_cancel_incoming_before_sending(self):
        board = self.board()
        self.tetris_well(board)
        board.pending.extend((Garbage(2, 3, 99), Garbage(3, 6, 99)))
        board.hard_drop()
        self.assertEqual(board.incoming, 1)
        self.assertEqual(board.pending[0].hole, 6)
        self.assertEqual(board.outgoing, 0)

    def test_garbage_waits_and_has_one_hole(self):
        board = self.board()
        board.pending.append(Garbage(2, 6, 1.5))
        board.now = 1.4
        board.apply_garbage()
        self.assertEqual(board.incoming, 2)
        board.now = 1.5
        board.apply_garbage()
        self.assertEqual(board.incoming, 0)
        for row in board.grid[-2:]:
            self.assertEqual(row.count(None), 1)
            self.assertIsNone(row[6])

    def test_garbage_cap_and_overflow(self):
        board = self.board()
        board.grid[0][0] = "J"
        board.pending.append(Garbage(12, 3, 0))
        board.apply_garbage()
        self.assertFalse(board.alive)
        self.assertEqual(board.incoming, 4)
        self.assertEqual(len(board.grid), HEIGHT)

    def test_attack_delivery_and_simultaneous_cancellation(self):
        match = Match(7)
        match.boards[0].outgoing = 4
        match.boards[1].outgoing = 2
        match.tick(0.02)
        self.assertEqual(match.boards[0].incoming, 0)
        self.assertEqual(match.boards[1].incoming, 2)
        self.assertAlmostEqual(match.boards[1].pending[0].ready_at, 1.52)

    def test_lock_delay_and_reset_limit(self):
        board = self.board()
        board.piece = Piece("O", x=3, y=20)
        board.tick(0.3)
        self.assertEqual(board.pieces_placed, 0)
        for index in range(15):
            self.assertTrue(board.move(1 if index % 2 == 0 else -1))
            board.tick(0.02)
        self.assertEqual(board.lock_resets, 15)
        board.tick(0.3)
        board.move(-1)
        board.tick(0.2)
        self.assertEqual(board.pieces_placed, 1)

    def test_soft_drop_and_speed_increase(self):
        normal, soft = self.board(), self.board()
        normal.tick(0.2)
        soft.tick(0.2, True)
        self.assertGreater(soft.piece.y, normal.piece.y)
        self.assertGreater(soft.score, 0)
        before = normal.gravity_interval
        normal.lines = 10
        self.assertEqual(normal.level, 2)
        self.assertLess(normal.gravity_interval, before)

    def test_spawn_collision_and_hidden_lockout(self):
        board = self.board()
        for x, y in board.piece.cells():
            board.grid[y][x] = "G"
        board.spawn(board.piece.kind)
        self.assertFalse(board.alive)
        board = self.board()
        board.piece = Piece("O")
        for x in (4, 5):
            board.grid[HIDDEN][x] = "G"
        board.hard_drop()
        self.assertFalse(board.alive)

    def test_winner_draw_and_finished_match_is_frozen(self):
        match = Match(2)
        match.boards[0].alive = False
        match.tick(0.01)
        self.assertTrue(match.finished)
        self.assertEqual(match.winner, 1)
        before = match.elapsed
        match.tick(9)
        match.action(1, "drop")
        self.assertEqual(match.elapsed, before)
        self.assertEqual(match.boards[1].pieces_placed, 0)
        match = Match(2)
        for board in match.boards:
            board.alive = False
        match.tick(0)
        self.assertIsNone(match.winner)

    def test_random_games_preserve_invariants(self):
        rng = random.Random(100)
        for seed in range(20):
            match = Match(seed)
            for _ in range(600):
                for player in (0, 1):
                    match.action(player, rng.choice(("left", "right", "rotate", "reverse", "drop", "hold")))
                match.tick(0.05, (rng.choice((False, True)), False))
                for board in match.boards:
                    self.assertEqual(len(board.grid), HEIGHT)
                    self.assertTrue(all(len(row) == WIDTH for row in board.grid))
                    self.assertGreaterEqual(board.incoming, 0)
                    if board.alive:
                        self.assertTrue(board.valid())
                if match.finished:
                    break
            self.assertTrue(match.finished)


if __name__ == "__main__":
    unittest.main()
