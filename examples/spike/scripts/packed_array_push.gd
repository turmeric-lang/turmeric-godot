@tool
extends SceneTree

# Regression driver for the Packed*Array push natives. packed_array_push.tur
# builds one array per family and hands each back through set_meta; every
# one must hold exactly what was pushed. Before the arena write-back fix all
# nine came back empty, with no diagnostic.
#
#   godot --headless --path examples/spike --script scripts/packed_array_push.gd

var fail_count := 0

func _expect(node: Node, key: String, want: Variant) -> void:
	if not node.has_meta(key):
		fail_count += 1
		printerr("[packed_array_push.gd] FAIL: ", key, " was never set")
		return
	var got: Variant = node.get_meta(key)
	if typeof(got) != typeof(want) or got != want:
		fail_count += 1
		printerr("[packed_array_push.gd] FAIL: ", key, ": expected ", want, ", got ", got)

func _init() -> void:
	var script := load("res://scripts/packed_array_push.tur")
	if script == null:
		printerr("[packed_array_push.gd] FAIL: load returned null")
		quit(1); return

	var node := Node.new()
	node.name = "PackedPushNode"
	node.set_script(script)
	root.add_child(node)

	await process_frame

	_expect(node, "byte_size", 2)
	_expect(node, "byte", PackedByteArray([222, 173]))
	_expect(node, "int32", PackedInt32Array([10, -20, 30]))
	_expect(node, "int64", PackedInt64Array([4294967296, -7]))
	_expect(node, "float32", PackedFloat32Array([7.25, -0.5]))
	_expect(node, "float64", PackedFloat64Array([7.1, 3.25]))
	_expect(node, "string", PackedStringArray(["alpha", "beta"]))
	_expect(node, "vec2", PackedVector2Array([Vector2(1.0, 0.5), Vector2(0.5, 1.0)]))
	_expect(node, "vec3", PackedVector3Array([Vector3(1.0, 2.0, 3.5), Vector3(-1.0, 0.25, 0.0)]))
	_expect(node, "color", PackedColorArray([Color(1.0, 0.5, 0.25, 1.0), Color(0.0, 0.0, 0.0, 0.5)]))

	if fail_count == 0:
		print("[packed_array_push.gd] all assertions passed")
		quit(0)
	else:
		printerr("[packed_array_push.gd] %d FAILURES" % fail_count)
		quit(1)
