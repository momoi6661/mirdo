extends SceneTree

const ANIM_PATH := "res://resources/animate/Kimodo/walking_into_running.res"
const WALK_REF := 2.23333333333333
const RUN_REF := 8.36666666666667
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
func root_z(anim:Animation,rt:int,t:float)->float: return anim.position_track_interpolate(rt,t).z
func speed(anim:Animation,rt:int,t:float)->float:
	var dt:=1.0/FPS; var a:float=max(0.0,t-dt); var b:float=min(anim.length,t+dt)
	return 0.0 if b<=a else (root_z(anim,rt,b)-root_z(anim,rt,a))/(b-a)
func _init():
	var anim:Animation=ResourceLoader.load(ANIM_PATH); var rt:=root_track(anim)
	print("Find walk_to_run_v2 start. walk_ref=",WALK_REF," run_ref=",RUN_REF)
	var c:=[]
	# 起点在稳定走路末段/加速开始前，终点固定到 run_loop_v2 起点。
	for sf in range(int(round(3.6*FPS)), int(round(6.4*FPS))+1):
		var s:float=float(sf)/FPS
		if RUN_REF - s < 1.0: continue
		var ps:=pose_score(anim,s,WALK_REF)
		var start_sp:float=speed(anim,rt,s)
		var end_sp:float=speed(anim,rt,RUN_REF)
		var dur:float=RUN_REF-s
		# 既要相位接近 walk，又不要太长；起点速度应仍是 walk 区间。
		var dur_penalty:float=abs(dur-2.9)*0.45
		var speed_penalty:float=abs(start_sp-1.1)*0.45
		var score:float=ps.score+dur_penalty+speed_penalty
		c.append({"s":s,"e":RUN_REF,"dur":dur,"score":score,"entry":ps.score,"max":ps.max,"max_name":ps.max_name,"start_speed":start_sp,"end_speed":end_sp,"rootZ":root_z(anim,rt,RUN_REF)-root_z(anim,rt,s)})
	c.sort_custom(func(a,b): return a.score<b.score)
	for i in range(min(20,c.size())):
		var d=c[i]
		print("#",i+1," s=","%0.4f"%d.s," e=","%0.4f"%d.e," dur=","%0.4f"%d.dur," score=","%0.3f"%d.score," entry=","%0.3f"%d.entry," max=","%0.2f"%d.max,"@",d.max_name," speed=","%0.3f"%d.start_speed,"->","%0.3f"%d.end_speed," rootZ=","%0.4f"%d.rootZ)
	quit()
