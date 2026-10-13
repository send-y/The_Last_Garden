"""Collect successful evidence only; does not run tests or modify game state."""
import json, pathlib, subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = pathlib.Path(__file__).resolve().parent
selections = {
    'frozen-core': ['run_tests.gd'],
    'hint-final': ['tool_progression_test.gd'],
    'final': ['tool_tiers_test.gd', 'npc_practical_work_test.gd'],
    'contract-final': ['recipe_learning_validation_test.gd', 'tool_learning_edges_test.gd', 'item_tool_properties_test.gd', 'item_tool_resource_test.gd', 'item_tool_npc_test.gd', 'farming_rules_test.gd'],
    'graphics-final': ['tool_tiers_render_test.tscn', 'crafting_integration_test.tscn', 'item_tool_water_test.gd', 'tool_request_test.gd'],
    'translations-final': ['starting_pantry_integration_test.tscn'],
    'dependencies-final-2': ['npc_work_query_cache_test.gd'],
    'farming-ui-final-2': ['farming_integration_test.tscn'],
    'dependencies-final': ['item_source_references_test.gd', 'npc_home_production_test.gd', 'npc_home_projects_test.gd', 'resident_home_projects_test.gd'],
    'presentation-fixed': ['inventory_cell_anchor_test.tscn', 'item_tool_ui_test.tscn'],
}
rows = []
for report, names in selections.items():
    evidence = json.loads((OUT / (report+'.json')).read_text(encoding='utf-8'))
    assert evidence['save_before'] == evidence['save_after']
    for name in names:
        row = next(row for row in evidence['checks'] if row['name'] == name)
        assert row['passed'] and row['exit'] == 0, (report, row)
        log = report+'-'+pathlib.Path(name).stem+('-graphic' if row['graphic'] else '')+'.log'
        assert (OUT/log).exists(), log
        rows.append(dict(row, source_report=report+'.json', log=log))
data = dict(checks=rows, save_sha256=evidence['save_after'], fps_benchmarks_run=False,
            scope='Selected successful contract checks; intermediate failures are not final evidence.')
(OUT/'verification-summary.json').write_text(json.dumps(data,indent=2),encoding='utf-8')
print('Collected', len(rows), 'successful checks')
