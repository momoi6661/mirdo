extends SceneTree

const STAND_PATH := "res://resources/animate/Kimodo/mirdo_stand_to_walk_fast.res"
const SRC_PATH := "res://resources/animate/Kimodo/walking_into_running.res"
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
func speed(anim:Animation,t:float)->float:
	var dt:=1.0/FPS; var a:float=max(0,t-dt); var b:float=min(anim.length,t+dt)
	return 0.0 if b<=a else (root_z(anim,b)-root_z(anim,a))/(b-a)
func _init():
	var stand:Animation=ResourceLoader.load(STAND_PATH)
	var src:Animation=ResourceLoader.load(SRC_PATH)
	var stand_end:=stand.length
	print("stand=",STAND_PATH," length=",stand.length," compare to walking_into_running")
	var c:=[]
	# 在稳定走路段找能接 stand_to_walk_fast 结尾的起点，同时要求后面 1.4~1.7s 能形成走路 loop。
	for f in range(int(round(0.0*FPS)), int(round(5.4*FPS))+1):
		var t:float=float(f)/FPS
		var ps:=pose_score(stand,stand_end,src,t)
		var sp:=speed(src,t)
		var score:float=ps.score + abs(sp-1.1)*0.35
		c.append({"t":t,"score":score,"pose":ps.score,"max":ps.max,"max_name":ps.max_name,"speed":sp})
	c.sort_custom(func(a,b): return a.score<b.score)
	print("\nBEST start candidates matching stand_to_walk_fast end")
	for i in range(min(25,c.size())):
		var d=c[i]
		print("#",i+1," t=","%0.4f"%d.t," score=","%0.3f"%d.score," pose=","%0.3f"%d.pose," max=","%0.2f"%d.max,"@",d.max_name," speed=","%0.3f"%d.speed)
	quit()
