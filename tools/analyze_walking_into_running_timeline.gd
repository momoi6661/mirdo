extends SceneTree

const ANIM_PATH := "res://resources/animate/Kimodo/walking_into_running.res"
const FPS := 30.0
var important := {
	"Hips": 3.0,"Spine": 1.5,"Chest": 1.5,"UpperChest": 1.2,"Head": 1.0,
	"LeftUpperArm": 1.2,"LeftLowerArm": 1.2,"RightUpperArm": 1.2,"RightLowerArm": 1.2,
	"LeftUpperLeg": 3.0,"LeftLowerLeg": 3.0,"LeftFoot": 2.5,
	"RightUpperLeg": 3.0,"RightLowerLeg": 3.0,"RightFoot": 2.5,
}
func bone_name(anim: Animation, i: int) -> String:
	var p := str(anim.track_get_path(i)); var idx := p.rfind(":"); return p.substr(idx+1) if idx >= 0 else p
func quat_deg(a: Quaternion,b: Quaternion)->float:
	var d: float = abs(a.dot(b)); d=clamp(d,-1.0,1.0); return rad_to_deg(2.0*acos(d))
func root_track(anim: Animation)->int:
	for i in range(anim.get_track_count()):
		if anim.track_get_type(i)==Animation.TYPE_POSITION_3D and bone_name(anim,i)=="Root": return i
	return -1
func pose_delta(anim: Animation, a: float, b: float)->float:
	var sum:=0.0; var ws:=0.0
	for i in range(anim.get_track_count()):
		if anim.track_get_type(i)!=Animation.TYPE_ROTATION_3D: continue
		var n:=bone_name(anim,i)
		if not important.has(n): continue
		var w: float=float(important[n])
		sum += quat_deg(anim.rotation_track_interpolate(i,a), anim.rotation_track_interpolate(i,b))*w
		ws += w
	return sum/max(ws,0.0001)
func _init():
	var anim: Animation=ResourceLoader.load(ANIM_PATH)
	if anim==null: print("LOAD_FAILED"); quit(1); return
	var rt:=root_track(anim)
	print("ANIM=", ANIM_PATH, " length=", anim.length, " loop=", anim.loop_mode, " tracks=", anim.get_track_count(), " root_track=", rt)
	print("time rootZ speed poseDelta")
	for f in range(0, int(ceil(anim.length*FPS))+1):
		var t: float=min(float(f)/FPS, anim.length)
		var dt:=1.0/FPS
		var a: float=max(0.0,t-dt); var b: float=min(anim.length,t+dt)
		var za:=anim.position_track_interpolate(rt,a).z
		var zb:=anim.position_track_interpolate(rt,b).z
		var speed: float=0.0 if b<=a else (zb-za)/(b-a)
		var pd: float=0.0 if f==0 else pose_delta(anim,max(0.0,t-dt),t)
		if f % 3 == 0 or f==int(ceil(anim.length*FPS)):
			print("t=","%0.3f"%t," rootZ=","%0.4f"%anim.position_track_interpolate(rt,t).z," speed=","%0.3f"%speed," pose=","%0.3f"%pd)
	quit()
