"""One-time fixture migration: explicit structure owner API, no lazy scans."""
from pathlib import Path
import re
root = Path(__file__).resolve().parents[2] / "game" / "tests"
for path in root.rglob("*.gd"):
    if path.name == "structure_index_test.gd":
        continue  # deliberate fault injection is part of this test
    source = path.read_text(encoding="utf-8-sig")
    updated = re.sub(r"(\w+)\.state\.structures\.append\(", r"\1.add_structure(", source)
    updated = re.sub(r"(\w+)\.state\.structures\.clear\(\)", r"\1.replace_structures([])", updated)
    updated = re.sub(r"(\w+)\.state\.structures\.pop_back\(\)", lambda m: f"{m[1]}.remove_structure({m[1]}.state.structures.back())", updated)
    updated = re.sub(r"(\w+)\.state\.structures\.remove_at\((\w+)\)", lambda m: f"{m[1]}.remove_structure({m[1]}.state.structures[{m[2]}])", updated)
    lines = updated.splitlines(keepends=True)
    for index, line in enumerate(lines):
        match = re.match(r"(\s*)(\w+)\.state\.structures = (.*?)(\r?\n)?$", line)
        if not match:
            continue
        indent, name, value, newline = match.groups()
        if value == "[":
            lines[index] = f"{indent}{name}.replace_structures([{newline or ''}"
            for following in range(index+1, len(lines)):
                if lines[following].strip() == "]":
                    lines[following] = lines[following].replace("]", "])", 1)
                    break
            else:
                raise RuntimeError(f"Unterminated fixture array: {path}:{index+1}")
        else:
            lines[index] = f"{indent}{name}.replace_structures({value}){newline or ''}"
    updated = "".join(lines)
    if updated != source:
        path.write_text(updated, encoding="utf-8", newline="\n")
        print(path.name)
