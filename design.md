# Humlex Brew Theme (Dark Default)

## Concept
A dark, cozy theme inspired by the Humlex beer icon:
- Pine greens for structure and navigation.
- Warm amber for energy and user actions.
- Cream/foam tones for readable text on dark surfaces.

## Core Tokens
| Token | Hex | Usage |
|---|---|---|
| `background` | `#0C1110` | Main canvas |
| `sidebarBackground` | `#080D0B` | Sidebar and chrome |
| `surfaceBackground` | `#131A16` | Cards, sheets, composer surface |
| `divider` | `#2B3A32` | Borders and separators |
| `textPrimary` | `#F4EFE3` | Primary body text |
| `textSecondary` | `#D9CBB1` | Metadata and labels |
| `textTertiary` | `#9F927D` | Placeholder and muted text |
| `accent` | `#1F8A4D` | Primary accents and active state |
| `userBubble` | `#2A2D31` | User message bubble (dark gray) |
| `userBubbleText` | `#F4EFE3` | Text inside user bubble |
| `composerBorderFocused` | `#2B3530` | Subtle focused border |

## Code + Syntax Tokens
| Token | Hex |
|---|---|
| `codeBackground` | `#0F1512` |
| `codeBorder` | `#264136` |
| `codeHeaderBackground` | `#15201A` |
| `syntaxKeyword` | `#F4B23A` |
| `syntaxString` | `#F6E4B3` |
| `syntaxComment` | `#6E7B69` |
| `syntaxNumber` | `#FF9F1A` |
| `syntaxType` | `#7BCF9C` |
| `syntaxFunction` | `#39A96B` |
| `syntaxPunctuation` | `#B3AA96` |
| `syntaxPlain` | `#F4EFE3` |

## Default Behavior
Humlex now defaults to this theme (`humlex-brew`) for:
- selected theme storage fallback
- environment default theme
- syntax highlighter fallback theme

## Accessibility Notes
- Primary text is intentionally high contrast against all dark surfaces.
- Amber is used as emphasis, while green remains the stable navigational accent.
- Muted text stays warm to avoid blue/gray fatigue in long chat sessions.

## Light Variant
`Humlex Brew Light` is now available as a separate selectable theme:

| Token | Hex | Usage |
|---|---|---|
| `background` | `#F4F1E8` | Main light canvas |
| `sidebarBackground` | `#ECE7DB` | Sidebar |
| `surfaceBackground` | `#FBF8F1` | Cards and composer |
| `divider` | `#C9C2B2` | Borders/separators |
| `textPrimary` | `#1B211D` | Main text |
| `textSecondary` | `#425046` | Labels/meta |
| `accent` | `#1F8A4D` | Primary accent |
| `userBubble` | `#3C4045` | User bubble dark gray |
| `userBubbleText` | `#F5F6F8` | User bubble text |
