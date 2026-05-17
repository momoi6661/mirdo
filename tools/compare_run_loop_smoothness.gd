extends SceneTree

const PATHS := [
	"res://resources/animate/Kimodo/run_forward_loop_short.res",
	"res://resources/animate/Kimodo/run_forward_loop_v2.res",
]
const FPS := 30.0
var important := {
	"Hips": 3.0,"Spine": 1.5,"Chest": 1.5,"UpperChest": 1.2,"Head": 1.0,
	"LeftUpperArm": 1.2,"LeftLowerArm": 1.2,"LeftHand": 0.8,"RightUpperArm": 1.2,"RightLowerArm": 1.2,"RightHand": 0.8,
	"LeftUpperLeg": 3.0,"LeftLowerLeg": 3.0,"LeftFoot": 2.5,"LeftToeBase": 1.2,
	"RightUpperLeg": 3.0,"RightLowerLeg": 3.0,"RightFoot": 2.5,"RightToeBase": 1.2,
}
func bone_name(anim: Animation,i:int)->String:
	var p:=str(anim.track_get_path(i)); var idx:=p.rfind(":"); return p.substr(idx+1) if idx>=0 else p
func quat_deg(a:Quaternion,b:Quaternion)->float:
	var d:float=abs(a.dot(b)); d=clamp(d,-1,1); return rad_to_deg(2*acos(d))
func root_track(anim:Animation)->int:
	for i in range(anim.get_track_count()):
		if anim.track_get_type(i)==Animation.TYPE_POSITION_3D and bone_name(anim,i)=="Root": return i
	return -1
func root_z(anim:Animation,rt:int,t:float)->float: return anim.position_track_interpolate(rt,t).z
func pose_score(anim:Animation,t0:float,t1:float)->Dictionary:
	var sum:=0.0; var ws:=0.0; var maxd:=0.0; var maxn:=""
	for i in range(anim.get_track_count()):
		if anim.track_get_type(i)!=Animation.TYPE_ROTATION_3D: continue
		var n:=bone_name(anim,i)
		if not important.has(n): continue
		var deg:=quat_deg(anim.rotation_track_interpolate(i,t0), anim.rotation_track_interpolate(i,t1))
		var w:float=float(important[n]); sum+=deg*w; ws+=w
		if deg>maxd: maxd=deg; maxn=n
	return {"score":sum/max(ws,0.0001),"max":maxd,"max_name":maxn}
func pose_delta_frame(anim:Animation,t:float)->float:
	var dt:=1.0/FPS
	return pose_score(anim,max(0.0,t-dt),min(anim.length,t)).score
func _init():
	for path in PATHS:
		var anim:Animation=ResourceLoader.load(path,"Animation",ResourceLoader.CACHE_MODE_IGNORE)
		var rt:=root_track(anim)
		var start_end: Dictionary=pose_score(anim,0.0,anim.length)
		var pre_end_delta: float=pose_delta_frame(anim,anim.length)
		var start_delta: float=float(pose_score(anim,0.0,min(anim.length,1.0/FPS)).score)
		var rz: float=root_z(anim,rt,anim.length)-root_z(anim,rt,0.0)
		print("\n",path)
		print("length=",anim.length," rootZ=",rz," speed=",rz/anim.length)
		print("pose start-end=",start_end.score," max=",start_end.max,"@",start_end.max_name)
		print("last-frame-delta=",pre_end_delta," first-frame-delta=",start_delta)
		for i in range(min(6,anim.get_track_count())):
			print("track",i," ",anim.track_get_path(i)," keys=",anim.track_get_key_count(i)," last=",anim.track_get_key_time(i,anim.track_get_key_count(i)-1))
	quit()

