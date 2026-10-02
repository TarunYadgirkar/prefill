def rect(x0, y0, x1, y1, r):
    return f'<rect x="{x0}" y="{y0}" width="{x1 - x0}" height="{y1 - y0}" rx="{r}" fill="#000"/>'


def pill(x0, y0, x1, y1):
    return rect(x0, y0, x1, y1, (y1 - y0) / 2)


PALETTES = {
    "a-slot": {
        "Harbor": "#14505A",
        "Night harbor": "#071E23",
        "Marigold": "#FFB43A",
        "Frost": "#EEF4F3",
        "Ink": "#0D2A30",
    },
    "b-shortlist": {
        "Paper": "#F5F0E7",
        "Linen": "#E2D8C8",
        "Persimmon": "#E85F3A",
        "Milk glass": "#FFFDF9",
        "Walnut": "#2B2520",
        "Espresso": "#151210",
    },
    "c-caret": {
        "Mint mist": "#E3F1EA",
        "Sage": "#BFDCCD",
        "Fern": "#0E7A55",
        "Spring": "#4FD39B",
        "Moss night": "#0B1914",
    },
}

A, B, C = (PALETTES[k] for k in ("a-slot", "b-shortlist", "c-caret"))

BOWL = '<path d="M452 204H600A156 156 0 0 1 600 516H452A56 56 0 0 1 396 460V260A56 56 0 0 1 452 204Z" fill="#000"/>'

KEY_ROW = "".join(rect(112 + i * 166, 664, 248 + i * 166, 812, 40) for i in range(5))

DIRECTIONS = {
    "a-slot": {
        "title": "A  Slot",
        "background": ([A["Harbor"], A["Night harbor"]], ["#0C2C32", "#030C0E"]),
        "groups": [
            {
                "translucency": 0.15,
                "layers": [
                    {"name": "chip-text", "glass": False, "fill": ((A["Ink"], 0.75), (A["Ink"], 0.8)),
                     "svg": pill(252, 330, 380, 354) + pill(196, 382, 436, 414)},
                    {"name": "chip", "fill": (A["Marigold"], A["Marigold"]), "svg": rect(132, 276, 496, 468, 96)},
                ],
            },
            {
                "translucency": 0.5,
                "shadow": "neutral",
                "layers": [
                    {"name": "bar-text", "glass": False, "fill": ((A["Ink"], 0.4), (A["Frost"], 0.4)),
                     "svg": rect(508, 352, 516, 476, 4) + pill(648, 370, 776, 392) + pill(592, 420, 832, 450)},
                    {"name": "bar", "fill": ((A["Frost"], 0.88), ("#9DB3B6", 0.5)),
                     "svg": pill(112, 304, 912, 524)},
                ],
            },
            {
                "translucency": 0.6,
                "shadow": "neutral",
                "shadow_opacity": 0.25,
                "layers": [
                    {"name": "keys", "fill": ((A["Frost"], 0.32), ("#9DB3B6", 0.22)), "svg": KEY_ROW},
                ],
            },
        ],
    },
    "b-shortlist": {
        "title": "B  Shortlist",
        "background": ([B["Paper"], B["Linen"]], ["#2A241F", B["Espresso"]]),
        "groups": [
            {
                "translucency": 0.15,
                "layers": [
                    {"name": "top-text", "glass": False, "fill": ((B["Milk glass"], 0.95), (B["Milk glass"], 0.95)),
                     "svg": '<g transform="rotate(-4 512 330)">' + '<circle cx="256" cy="330" r="44" fill="#000"/>'
                     + pill(336, 290, 520, 314) + pill(336, 340, 760, 372) + "</g>"},
                    {"name": "top", "fill": (B["Persimmon"], B["Persimmon"]),
                     "svg": '<g transform="rotate(-4 512 330)">' + pill(166, 236, 858, 424) + "</g>"},
                ],
            },
            {
                "translucency": 0.55,
                "shadow": "neutral",
                "shadow_opacity": 0.35,
                "layers": [
                    {"name": "rows-text", "glass": False, "fill": ((B["Walnut"], 0.3), (B["Milk glass"], 0.32)),
                     "svg": '<circle cx="288" cy="560" r="34" fill="#000"/>' + pill(350, 546, 700, 574)
                     + '<circle cx="314" cy="722" r="28" fill="#000"/>' + pill(370, 711, 660, 733)},
                    {"name": "rows", "fill": ((B["Milk glass"], 0.85), ("#6E625A", 0.55)),
                     "svg": pill(214, 490, 810, 630) + pill(250, 662, 774, 782)},
                ],
            },
        ],
    },
    "c-caret": {
        "title": "C  Caret",
        "background": ([C["Mint mist"], C["Sage"]], ["#12261E", C["Moss night"]]),
        "groups": [
            {
                "translucency": 0.2,
                "layers": [
                    {"name": "bowl-text", "glass": False, "fill": ((C["Moss night"], 0.6), (C["Moss night"], 0.65)),
                     "svg": pill(460, 316, 580, 342) + pill(460, 374, 676, 408)},
                    {"name": "bowl", "fill": (C["Spring"], C["Spring"]), "svg": BOWL},
                ],
            },
            {
                "translucency": 0.1,
                "layers": [
                    {"name": "stem", "fill": (C["Fern"], "#2AA673"), "svg": rect(268, 204, 364, 820, 48)},
                ],
            },
        ],
    },
}
