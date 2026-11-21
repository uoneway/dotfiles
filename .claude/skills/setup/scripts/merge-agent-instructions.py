"""Replace matching level-two sections and append new machine instructions."""

import re
import sys
from pathlib import Path


HEADING = re.compile(r"^ {0,3}##(?:[ \t]+(.*)|$)")
FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")


def sections(text):
    title = None
    lines = []
    fence = None
    for line in text.splitlines(keepends=True):
        marker = FENCE.match(line)
        if fence:
            if marker and marker[1].startswith(fence) and not marker[2].strip():
                fence = None
        elif marker and (marker[1][0] == "~" or "`" not in marker[2]):
            fence = marker[1]
        else:
            heading = HEADING.match(line)
            if heading:
                yield title, "".join(lines)
                title = re.sub(r"(?:^|[ \t]+)#+[ \t]*$", "", heading[1] or "").strip()
                lines = []
        lines.append(line)
    yield title, "".join(lines)


def merge(base, addition):
    base_sections = list(sections(base))
    extra_sections = list(sections(addition))
    base_titles = {title for title, _ in base_sections if title is not None}
    replacements = {title: body for title, body in extra_sections if title in base_titles}
    if not replacements:
        return base + "\n" + addition

    replaced_titles = set(replacements)
    output = []
    for title, body in base_sections:
        if title in replaced_titles:
            body = replacements.pop(title, "")
        output.append(body)
    output.extend(body for title, body in extra_sections if title not in base_titles)
    return "\n\n".join(body.strip("\n") for body in output if body.strip("\n")) + "\n"


if __name__ == "__main__":
    base_path, addition_path = map(Path, sys.argv[1:])
    sys.stdout.write(merge(base_path.read_text(encoding="utf-8"), addition_path.read_text(encoding="utf-8")))
