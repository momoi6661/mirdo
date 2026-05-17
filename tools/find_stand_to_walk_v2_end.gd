extends SceneTree

const WALK_PATH := "res://resources/animate/Kimodo/walk_forward_loop_v2.res"
const SRC_PATHS := [
	"res://resources/animate/Kimodo/mirdo_stand_to_walk.res",
	"res://resources/animate/Kimodo/mirdo_stand_to_walk_fast.res",
	"res://resources/animate/Kimodo/walk.res",
	"res://resources/animate/Kimodo/walking_into_running.res",
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
func find_track(anim:Animation,n:String,typ:int)->int:
	for i in range(anim.get_track_count()):
		if anim.track_get_type(i)==typ and bone_name(anim,i)==n: return i
	return -1
func quat_deg(a:Quaternion,b:Quaternion)->float:
	var d:float=abs(a.dot(b)); d=clamp(d,-1,1); return rad_to_deg(2*acos(d))
func pose_score(a:Animation,ta:float,b:Animation,tb:float)->Dictionary:
	var sum:=0.0; var ws:=0.0; var maxd:=0.0; var maxn:=""
	for ia in range(a.get_track_count()):
		if a.track_get_type(ia)!=Animation.TYPE_ROTATION_3D: continue
		var n:=bone_name(a,ia)
		if not important.has(n): continue
		var ib:=find_track(b,n,Animation.TYPE_ROTATION_3D)
		if ib<0: continue
		var deg:=quat_deg(a.rotation_track_interpolate(ia,ta), b.rotation_track_interpolate(ib,tb))
		var w:float=float(important[n]); sum+=deg*w; ws+=w
		if deg>maxd: maxd=deg; maxn=n
	return {"score":sum/max(ws,0.0001),"max":maxd,"max_name":maxn}
func root_z(anim:Animation,t:float)->float:
	var rt:=find_track(anim,"Root",Animation.TYPE_POSITION_3D)
	return 0.0 if rt<0 else anim.position_track_interpolate(rt,t).z
func _init():
	var walk:Animation=ResourceLoader.load(WALK_PATH)
	print("Target walk loop start: ", WALK_PATH, " length=", walk.length)
	for path in SRC_PATHS:
		var src:Animation=ResourceLoader.load(path)
		if src==null: continue
		var c:=[]
		for f in range(0, int(round(src.length*FPS))+1):
			var t:float=min(float(f)/FPS, src.length)
			var ps:=pose_score(src,t,walk,0.0)
			c.append({"t":t,"score":ps.score,"max":ps.max,"max_name":ps.max_name,"rootZ":root_z(src,t)})
		c.sort_custom(func(a,b): return a.score<b.score)
		print("\nSOURCE ", path, " length=", src.length)
		for i in range(min(8,c.size())):
			var d=c[i]
			print("#",i+1," t=","%0.4f"%d.t," score=","%0.3f"%d.score," max=","%0.2f"%d.max,"@",d.max_name," rootZ=","%0.4f"%d.rootZ)
	quit()
