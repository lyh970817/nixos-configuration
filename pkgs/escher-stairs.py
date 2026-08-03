"""Animated Escher-inspired impossible staircase."""

from __future__ import annotations

import argparse
import curses
import math
import time
from dataclasses import dataclass


@dataclass(frozen=True)
class Point:
    x: int
    y: int


def safe_write(
    window: curses.window,
    y: int,
    x: int,
    text: str,
    attributes: int = 0,
) -> None:
    """Draw safely, including while the terminal is being resized."""
    height, width = window.getmaxyx()

    if y < 0 or y >= height or x >= width:
        return

    if x < 0:
        text = text[-x:]
        x = 0

    text = text[: max(0, width - x)]
    if not text:
        return

    try:
        window.addstr(y, x, text, attributes)
    except curses.error:
        pass


def make_staircase(cx: int, cy: int, steps: int) -> list[Point]:
    """Create a closed diamond-shaped sequence of stair treads."""
    x = cx - 3 * steps
    y = cy
    points: list[Point] = []

    directions = (
        (3, -1),   # apparently ascending northeast
        (3, 1),    # apparently ascending southeast
        (-3, 1),   # apparently ascending southwest
        (-3, -1),  # apparently ascending northwest
    )

    for dx, dy in directions:
        for _ in range(steps):
            points.append(Point(x, y))
            x += dx
            y += dy

    return points


def draw_stair_segment(
    window: curses.window,
    start: Point,
    end: Point,
    attributes: int,
    tread: str = "━━",
) -> None:
    safe_write(window, start.y, start.x, tread, attributes)

    dx = end.x - start.x
    dy = end.y - start.y
    connector = "╱" if dx * dy < 0 else "╲"

    if dx > 0:
        safe_write(
            window,
            start.y + dy,
            start.x + 2,
            connector,
            attributes,
        )
    else:
        safe_write(
            window,
            start.y + dy,
            start.x - 1,
            connector,
            attributes,
        )


def draw_staircase(
    window: curses.window,
    path: list[Point],
    structure_attributes: int,
    shadow_attributes: int,
) -> None:
    """Draw a second displaced path to create isometric depth."""
    underside = [Point(point.x, point.y + 2) for point in path]

    for index, start in enumerate(underside):
        end = underside[(index + 1) % len(underside)]
        draw_stair_segment(
            window,
            start,
            end,
            shadow_attributes,
            tread="──",
        )

    # Add occasional vertical faces between the top and underside.
    for index, point in enumerate(path):
        if index % 2 == 0:
            safe_write(
                window,
                point.y + 1,
                point.x + 1,
                "│",
                shadow_attributes,
            )

    for index, start in enumerate(path):
        end = path[(index + 1) % len(path)]
        draw_stair_segment(
            window,
            start,
            end,
            structure_attributes,
        )


def draw_walker(
    window: curses.window,
    point: Point,
    next_point: Point,
    phase: int,
    attributes: int,
) -> None:
    """Draw a tiny two-frame walking figure."""
    facing_right = next_point.x >= point.x
    head_x = point.x + (1 if facing_right else 0)

    safe_write(window, point.y - 2, head_x, "●", attributes)

    if facing_right:
        body = "╱│" if phase == 0 else "│╲"
    else:
        body = "│╲" if phase == 0 else "╱│"

    safe_write(window, point.y - 1, point.x, body, attributes)


def draw_background(
    window: curses.window,
    elapsed: float,
    attributes: int,
) -> None:
    """Draw sparse, slowly twinkling points in the background."""
    height, width = window.getmaxyx()

    for index in range(max(8, width // 14)):
        x = (index * 37 + 11) % width
        y = (index * 17 + 5) % height

        pulse = math.sin(elapsed * 0.45 + index * 1.7)
        glyph = "∙" if pulse > 0.65 else "·"

        safe_write(window, y, x, glyph, attributes)


def animate(
    screen: curses.window,
    fps: float,
    requested_steps: int,
    show_background: bool,
) -> None:
    try:
        curses.curs_set(0)
    except curses.error:
        pass

    screen.nodelay(True)
    screen.keypad(True)

    has_colour = curses.has_colors()

    if has_colour:
        curses.start_color()
        curses.use_default_colors()

        curses.init_pair(1, curses.COLOR_WHITE, -1)
        curses.init_pair(2, curses.COLOR_CYAN, -1)
        curses.init_pair(3, curses.COLOR_BLUE, -1)

    structure_attributes = (
        (curses.color_pair(1) if has_colour else 0)
        | curses.A_BOLD
    )
    walker_attributes = (
        (curses.color_pair(2) if has_colour else 0)
        | curses.A_BOLD
    )
    shadow_attributes = (
        (curses.color_pair(3) if has_colour else 0)
        | curses.A_DIM
    )

    frame = 0
    next_frame_time = time.monotonic()

    while True:
        key = screen.getch()

        if key in (ord("q"), 27):
            return

        height, width = screen.getmaxyx()
        screen.erase()

        if show_background:
            draw_background(
                screen,
                time.monotonic(),
                curses.A_DIM,
            )

        # Reduce the staircase automatically in smaller terminals.
        steps = min(
            requested_steps,
            max(3, (width - 12) // 6),
            max(3, (height - 8) // 2),
        )

        path = make_staircase(
            cx=width // 2,
            cy=height // 2,
            steps=steps,
        )

        draw_staircase(
            screen,
            path,
            structure_attributes,
            shadow_attributes,
        )

        # Move one tread every two rendered frames.
        walker_index = (frame // 2) % len(path)
        current_point = path[walker_index]
        next_point = path[(walker_index + 1) % len(path)]

        draw_walker(
            screen,
            current_point,
            next_point,
            phase=(frame // 2) % 2,
            attributes=walker_attributes,
        )

        if width < 36 or height < 12:
            safe_write(
                screen,
                0,
                0,
                "Resize terminal",
                curses.A_BOLD,
            )

        screen.refresh()
        frame += 1

        next_frame_time += 1 / fps
        delay = next_frame_time - time.monotonic()

        if delay > 0:
            time.sleep(delay)
        else:
            next_frame_time = time.monotonic()


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Animated Escher-inspired impossible staircase."
    )
    parser.add_argument(
        "--fps",
        type=float,
        default=8,
        help="Frames per second; default: 8",
    )
    parser.add_argument(
        "--steps",
        type=int,
        default=8,
        help="Number of steps on each side; default: 8",
    )
    parser.add_argument(
        "--no-stars",
        action="store_true",
        help="Disable the sparse background dots",
    )

    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()

    if arguments.fps <= 0:
        raise SystemExit("--fps must be positive")

    if arguments.steps < 3:
        raise SystemExit("--steps must be at least 3")

    curses.wrapper(
        animate,
        arguments.fps,
        arguments.steps,
        not arguments.no_stars,
    )


if __name__ == "__main__":
    main()
