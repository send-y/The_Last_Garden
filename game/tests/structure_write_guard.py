"""Limited source guard; independent runtime checks cover unrecognised aliases.

Run from the repository: python game/tests/structure_write_guard.py
Only named bootstrap functions and the structure owner may write records.
"""
from pathlib import Path
import re

MUTATORS = r"(?:append|append_array|push_front|push_back|erase|remove_at|clear|pop_back|pop_front|resize|insert|sort|sort_custom|reverse|assign|fill)"
BOOTSTRAP = {
    "simulation/systems/save_migrations.gd": {"_normalize_state"},
    "simulation/systems/construction_state.gd": {"_normalize_structures"},
    "dev/resident_homes_scenario.gd": {"initial_state", "_add_room"},
    "dev/settlement_stress_scenario.gd": {"build"},
    "dev/mechanics_lab_scenarios.gd": {"build"},
    "simulation/world_rules.gd": {"create_new_game_state"},
    # Only these tests intentionally inject an illegal live write.
    "structure_index_test.gd": {"run", "_test_home_facts"},
}

def violations(source):
    aliases = set()
    fresh = set()
    found = []
    for number, raw in enumerate(source.splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if re.match(r"(?:static )?func ", line):
            aliases.clear()
            fresh.clear()
        assignment = re.search(r"(?:var\s+)?(\w+)(?:\s*:\s*\w+)?\s*(?::=|=(?!=))\s*(.+)", line)
        if assignment:
            name, value = assignment.groups()
            source_root = re.match(r"(\w+)(?:\.|\[)", value)
            if (value.startswith(("{", "[")) or re.search(r"\b(?:create_new_game_state|create_new_state|export_state|get_state|get_structures|_enclosed_room_state)\(", value)
                    or ".duplicate(" in value or (source_root and source_root[1] in fresh)):
                fresh.add(name)
            elif re.search(r"\.structures\b|\[\s*['\"]structures['\"]\s*\]|\.get\(\s*['\"]structures['\"]|_find_structure\(", value) and ".duplicate(" not in value:
                aliases.add(name)
            elif value.strip() in aliases:
                aliases.add(name)
        loop = re.match(r"for (\w+)(?:\s*:\s*\w+)? in (.+):", line)
        if loop and (re.search(r"\.structures\b", loop[2]) or loop[2] in aliases):
            loop_root = re.match(r"(\w+)(?:\.|\[)", loop[2])
            if loop_root and loop_root[1] in fresh:
                fresh.add(loop[1])
            else:
                aliases.add(loop[1])
        direct = re.search(r"(?:\w+\.)+structures|\w+\[\s*['\"]structures['\"]\s*\]", line)
        write = False
        if direct:
            tail = line[direct.end():]
            write = bool(re.match(r"\s*(?:=(?!=)|\[[^\]]+\]\s*=(?!=)|\." + MUTATORS + r"\s*\()", tail))
            if direct[0].split(".")[0].split("[")[0] in fresh: write = False
        # Named state fields, plus simple aliases. Reads and fresh local arrays pass.
        field = re.search(r"(\w+)(?:\.(?:open|lit)|\[['\"](?:open|lit)['\"]\])\s*=(?!=)", line)
        write |= bool(field and field[1] not in fresh)
        for alias in aliases:
            write |= bool(re.search(r"\b" + re.escape(alias) + r"(?:\." + MUTATORS + r"\s*\(|(?:\.\w+|\[[^\]]+\])+\s*=(?!=))", line))
        if write:
            found.append(number)
    return found

def check_tree(root):
    errors = []
    for path in sorted(root.rglob("*.gd")):
        relative = path.relative_to(root).as_posix()
        if relative == "construction/structure_index.gd":
            continue
        source = path.read_text(encoding="utf-8-sig")
        scopes = {}
        function = ""
        for number, line in enumerate(source.splitlines(), 1):
            match = re.match(r"(?:static )?func\s+(\w+)", line)
            if match:
                function = match.group(1)
            scopes[number] = function
        for number in violations(source):
            if scopes[number] not in BOOTSTRAP.get(relative, set()):
                errors.append(f"{relative}:{number}: live structure write outside owner")
    return errors

if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1] / "src"
    errors = check_tree(root)
    errors += check_tree(root.parent / "tests")
    print("\n".join(errors) if errors else "STRUCTURE_WRITE_GUARD: PASS")
    raise SystemExit(bool(errors))
