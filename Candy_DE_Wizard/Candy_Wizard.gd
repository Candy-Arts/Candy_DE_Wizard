#!###########################################################################################
#!																							#
#!       THIS SCRIPT MAY CONTAIN CODE THAT IS THE INTELLECTUAL PROPERTY OF CANDY ARTS       #
#!                             Copyright © 2025-2026 Candy Arts                             #
#!																							#
#!    Such code may only be used in compliance with the appropriate Candy Arts licenses.    #
#!                Any unauthorized use may constitute copyright infringement.               #
#!																							#
#!###########################################################################################


@tool
extends EditorPlugin


const WizardDock = preload("Scripts/Wizard_Dock.gd")
const TestRequests = preload("Scripts/Test_Requests.gd")

var dock: EditorDock = null
var test_requests: Node = null


func _enter_tree() -> void:
	dock = WizardDock.new()
	dock.wizard_version = _wizard_version()
	add_dock(dock)
	test_requests = TestRequests.new()
	add_child(test_requests)


func _exit_tree() -> void:
	if dock != null:
		remove_dock(dock)
		dock.queue_free()
		dock = null
	if test_requests != null:
		test_requests.queue_free()
		test_requests = null


#* Version from plugin.cfg:
func _wizard_version() -> String:
	var config := ConfigFile.new()
	var config_path: String = (get_script() as Script).resource_path.get_base_dir().path_join("plugin.cfg")
	if config.load(config_path) != OK:
		return "0.0.0"
	return str(config.get_value("plugin", "version", "0.0.0"))
