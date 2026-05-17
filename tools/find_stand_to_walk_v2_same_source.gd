extends SceneTree

const SRC_PATH := "res://resources/animate/Kimodo/walking_into_running.res"
const WALK_START := 2.8
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
func root_track(anim:Animation)->int:
	for i in range(anim.get_track_count()):
		if anim.track_get_type(i)==Animation.TYPE_POSITION_3D and bone_name(anim,i)=="Root": return i
	return -1
func root_z(anim:Animation,rt:int,t:float)->float:
	return anim.position_track_interpolate(rt,t).z
func speed(anim:Animation,rt:int,t:float)->float:
	var dt:=1.0/FPS; var a:float=max(0.0,t-dt); var b:float=min(anim.length,t+dt)
	return 0.0 if b<=a else (root_z(anim,rt,b)-root_z(anim,rt,a))/(b-a)
func _init():
	var anim:Animation=ResourceLoader.load(SRC_PATH)
	var rt:=root_track(anim)
	print("Find stand_to_walk_v2 in same source, ending at walk_start=", WALK_START)
	print("source=", SRC_PATH, " length=", anim.length)
	var c:=[]
	# 结束固定 walk_start，在前面找起点。目标是起步不要太长，且结尾自然进入 walk_start。
	for sf in range(0, int(round((WALK_START - 0.35)*FPS))+1):
		var s:float=float(sf)/FPS
		var dur:float=WALK_START-s
		if dur < 0.45 or dur > 1.6: continue
		var ps:=pose_score(anim,s,WALK_START)
		var ss:float=speed(anim,rt,s)
		var es:float=speed(anim,rt,WALK_START)
		var rz:float=root_z(anim,rt,WALK_START)-root_z(anim,rt,s)
		# 不要求首尾姿态相似，因为这是过渡；更偏好合理长度和从低速进入 walk。
		var score:float=abs(dur-0.9)*1.2 + abs(es-0.95)*0.4 + max(0.0, ss-1.15)*0.8 + ps.score*0.08
		c.append({"s":s,"e":WALK_START,"dur":dur,"score":score,"pose":ps.score,"max":ps.max,"max_name":ps.max_name,"ss":ss,"es":es,"rootZ":rz})
	c.sort_custom(func(a,b): return a.score<b.score)
	for i in range(min(25,c.size())):
		var d=c[i]
		print("#",i+1," s=","%0.4f"%d.s," e=","%0.4f"%d.e," dur=","%0.4f"%d.dur," score=","%0.3f"%d.score," pose=","%0.3f"%d.pose," max=","%0.2f"%d.max,"@",d.max_name," speed=","%0.3f"%d.ss,"->","%0.3f"%d.es," rootZ=","%0.4f"%d.rootZ)
	quit()
