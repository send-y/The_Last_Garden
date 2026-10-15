extends Logger
var _mutex := Mutex.new()
var _entries: Array[Dictionary] = []
func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	var traces: Array[String] = []
	for trace: ScriptBacktrace in script_backtraces: traces.append(trace.format().left(4096))
	var entry := {"time":Time.get_unix_time_from_system(),"type":error_type,"function":function,"file":file,"line":line,"code":code.left(4096),"message":rationale.left(4096),"backtraces":traces}
	_mutex.lock(); _entries.append(entry)
	if _entries.size()>128: _entries.pop_front()
	_mutex.unlock()
func snapshot(limit: int = 50) -> Array:
	_mutex.lock()
	var result := _entries.slice(maxi(0,_entries.size()-clampi(limit,1,128))).duplicate(true)
	_mutex.unlock()
	return result
