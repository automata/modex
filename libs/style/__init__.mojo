"""Minimal ANSI style helpers for terminal output."""

fn ansi_reset() -> String:
    return "\x1b[0m"


fn ansi_dim() -> String:
    return "\x1b[2m"


fn ansi_bold() -> String:
    return "\x1b[1m"


fn ansi_blue() -> String:
    return "\x1b[34m"


fn ansi_cyan() -> String:
    return "\x1b[36m"


fn ansi_green() -> String:
    return "\x1b[32m"


fn ansi_yellow() -> String:
    return "\x1b[33m"


fn ansi_magenta() -> String:
    return "\x1b[35m"


fn style(text: String, color: String = "", bold: Bool = False, dim: Bool = False) -> String:
    var prefix = String()
    if bold:
        prefix += ansi_bold()
    if dim:
        prefix += ansi_dim()
    prefix += color
    return prefix + text + ansi_reset()
