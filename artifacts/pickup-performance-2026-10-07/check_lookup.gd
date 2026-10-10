extends "res://tests/run_tests.gd"

func _run() -> void:
	_test_collection_lookup_avoids_surface_scan()
	if _failures > 0:
		push_error("FAIL: %d collection lookup assertions" % _failures)
		quit(1)
		return
	print("PASS: collection lookup without surface scans")
	quit(0)
