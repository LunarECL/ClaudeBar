# Themes — design

> Applies [the design](../../architecture/ARCHITECTURE.md) to how ClaudeBar
> looks. Users: [README.md](README.md). The code is the reference for every
> property: `Sources/App/Theme/AppThemeProvider.swift`.

## The shape

- **A theme is a value**, one type implementing `AppThemeProvider`: its colours,
  gradients, corner radii, fonts and default status colours. It registers once
  in `ThemeRegistry.registerBuiltInThemes()`; nothing else lists themes.
- **Views ask the theme, never which theme.** A view reads
  `@Environment(\.appTheme)` and uses its properties — card backgrounds are
  `theme.cardGradient` and `theme.glassBorder`. A view that checks for the CLI
  or Christmas theme is the old system and is replaced, not extended.
- **A new property gets a default** in the protocol extension (`cardBorderWidth`
  is `1`, `cardShadow` is none), so adding one never edits every theme.
- **Shared colours live in `BaseTheme`**; a theme takes them by name instead of
  repeating the values.

## Imported terminal themes

An `.itermcolors` file becomes a theme in four steps, each its own piece:

| Step | Rule | Piece |
|---|---|---|
| parse | 16 ANSI colours plus background and foreground, or the import fails | `ITermColorsParser` → `TerminalColorScheme` |
| map | red → critical, green → healthy, yellow → warning, cyan and blue → the accents; cards and glass are derived from the background; text tiers from the foreground | `TerminalThemeGenerator` |
| keep | the parsed colours, not the file, as JSON in `~/.claudebar/themes/` | `ImportedThemeStore` |
| load | regenerated and registered at every launch, so a better mapping reaches old imports | `ThemeRegistry` |

Another terminal format is one more parser that produces a
`TerminalColorScheme`; the mapping and the theme don't change.

Status colours a person chooses sit on top of every theme:
[status colors design](../status-colors/design.md).
