extends SceneTree
func _initialize():
 var code=load("res://scripts/offroad_main.gd")
 assert(not code.automatic_recovery_needed(Vector3(-561,74,239),"utah"))
 assert(not code.automatic_recovery_needed(Vector3(1019,20,-1019),"utah"))
 assert(code.automatic_recovery_needed(Vector3(1021,20,0),"utah"))
 assert(code.automatic_recovery_needed(Vector3(0,-51,0),"utah"))
 assert(code.automatic_recovery_needed(Vector3(NAN,20,0),"utah"))
 assert(code.automatic_recovery_needed(Vector3(320,20,0),"canyon"))
 assert(not code.automatic_recovery_needed(Vector3(360,20,0),"legacy"))
 assert(code.automatic_recovery_needed(Vector3(366,20,0),"legacy"))
 print("PASS: Utah and legacy recovery boundaries, fall and nonfinite detection")
 quit()
