extends SceneTree

const ANIM_PATH := "res://resources/animate/Kimodo/walking_into_running.res"
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
	return {"rot":sum/max(ws,0.0001),"max":maxd,"max_name":maxn}
func scan(anim:Animation, rt:int, label:String, start_min:float,start_max:float,dur_min:float,dur_max:float, speed_min:float,speed_max:float)->Array:
	var c:=[]
	for sf in range(int(round(start_min*FPS)), int(round(start_max*FPS))+1):
		var s:float=float(sf)/FPS
		for df in range(int(round(dur_min*FPS)), int(round(dur_max*FPS))+1):
			var dur:float=float(df)/FPS; var e:float=s+dur
			if e>anim.length: continue
			var rz:float=root_z(anim,rt,e)-root_z(anim,rt,s); var sp:float=rz/dur
			if sp<speed_min or sp>speed_max: continue
			var ps:=pose_score(anim,s,e)
			var score:float=ps.rot + abs(sp - ((speed_min+speed_max)/2.0))*0.15
			c.append({"s":s,"e":e,"dur":dur,"score":score,"rot":ps.rot,"max":ps.max,"max_name":ps.max_name,"rootZ":rz,"speed":sp})
	c.sort_custom(func(a,b): return a.score<b.score)
	print("\n",label)
	for i in range(min(15,c.size())):
		var d=c[i]
		print("#",i+1," s=","%0.4f"%d.s," e=","%0.4f"%d.e," dur=","%0.4f"%d.dur," score=","%0.3f"%d.score," rot=","%0.3f"%d.rot," max=","%0.2f"%d.max,"@",d.max_name," rootZ=","%0.4f"%d.rootZ," speed=","%0.3f"%d.speed)
	return c
func _init():
	var anim:Animation=ResourceLoader.load(ANIM_PATH); var rt:=root_track(anim)
	print("ANIM len=",anim.length," rt=",rt)
	var walk:=scan(anim,rt,"WALK_LOOP_CAND",0.3,5.2,1.0,1.7,0.75,1.35)
	var run:=scan(anim,rt,"RUN_LOOP_CAND",7.4,9.3,0.55,1.1,2.1,3.2)
	# 找 walk_to_run：终点尽量靠近 run loop 起点，起点从稳定走路相位中选，长度别太长。
	print("\nRECOMMEND_BOUNDARIES")
	if walk.size()>0: print("walk_loop_v2 ", "%0.4f"%walk[0].s, "..", "%0.4f"%walk[0].e)
	if run.size()>0: print("run_loop_v2 ", "%0.4f"%run[0].s, "..", "%0.4f"%run[0].e)
	quit()
