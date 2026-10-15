extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var script_path := "res://addons/garden_bridge/bridge.gd"
	if not ResourceLoader.exists(script_path):
		print("FAIL: runtime Garden Bridge missing"); quit(1); return
	var bridge = get_root().get_node_or_null("GardenDebugBridge")
	if bridge==null:
		print("FAIL: bridge autoload not installed"); quit(1); return
	if bridge.enabled:
		print("FAIL: ordinary isolated test must disable IPC"); quit(1); return
	print("PASS: bridge is disabled in ordinary isolated tests")
	quit(0)
