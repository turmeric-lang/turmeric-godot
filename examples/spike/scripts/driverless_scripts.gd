@tool
extends SceneTree

# Runs the smoke scripts that print rather than assert and so never had a
# driver of their own. That is how two of them stopped elaborating against
# the typed prelude without anyone noticing: nothing loaded them.
#
# Each must load, attach to a Node and get through _ready. tools/run-drivers.sh
# additionally requires the last line each one prints, so a _ready that stops
# half way is caught too.
#
#   godot --headless --path examples/spike --script scripts/driverless_scripts.gd

const SCRIPTS := [
	"dict_array_roundtrip",
	"packed_array_roundtrip",
	"vararg_dispatch",
]

func _init() -> void:
	var fail_count := 0
	for name in SCRIPTS:
		var script = load("res://scripts/%s.tur" % name)
		if script == null:
			fail_count += 1
			printerr("[driverless_scripts.gd] FAIL: ", name, ".tur: load returned null")
			continue
		var node := Node.new()
		node.name = name
		node.set_script(script)
		root.add_child(node)
		await process_frame
		print("[driverless_scripts.gd] ran ", name)
		node.queue_free()

	if fail_count == 0:
		print("[driverless_scripts.gd] all scripts loaded and ran")
		quit(0)
	else:
		printerr("[driverless_scripts.gd] %d FAILURES" % fail_count)
		quit(1)
