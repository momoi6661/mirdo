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
func speed(anim:Animation,rt:int,t:float)->float:
	var dt:=1.0/FPS; var a:float=max(0,t-dt); var b:float=min(anim.length,t+dt)
	return 0.0 if b<=a else (root_z(anim,rt,b)-root_z(anim,rt,a))/(b-a)
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
func print_c(label:String,d:Dictionary)->void:
	print(label," s=","%0.4f"%d.s," e=","%0.4f"%d.e," dur=","%0.4f"%d.dur," score=","%0.3f"%d.score," pose=","%0.3f"%d.pose," max=","%0.2f"%d.max,"@",d.max_name," rootZ=","%0.4f"%d.rootZ," speed=","%0.3f"%d.speed," sSpeed=","%0.3f"%d.sspeed," eSpeed=","%0.3f"%d.espeed)
func _init():
	var anim:Animation=ResourceLoader.load(ANIM_PATH); var rt:=root_track(anim)
	print("Find short walk_to_run: not gradual, jump from walk-ish into run-ish")
	var c:=[]
	# 在速度跃迁区找短段：起点仍接近走/快走，终点已经进入跑步速度；长度控制 0.45~1.10s。
	for sf in range(int(round(6.6*FPS)), int(round(8.1*FPS))+1):
		var s:float=float(sf)/FPS
		for df in range(int(round(0.45*FPS)), int(round(1.10*FPS))+1):
			var dur:float=float(df)/FPS; var e:float=s+dur
			if e>8.6667: continue
			var ss:float=speed(anim,rt,s); var es:float=speed(anim,rt,e)
			if ss>2.15: continue
			if es<2.35: continue
			var ps:=pose_score(anim,s,e)
			var rz:float=root_z(anim,rt,e)-root_z(anim,rt,s)
			# 短优先，终点跑速优先；不强求首尾同姿态，因为这是过渡动作。
			var score:float=dur*1.4 + abs(es-2.75)*0.35 + max(0.0, ss-1.9)*0.5 + ps.score*0.12
			c.append({"s":s,"e":e,"dur":dur,"score":score,"pose":ps.score,"max":ps.max,"max_name":ps.max_name,"rootZ":rz,"speed":rz/dur,"sspeed":ss,"espeed":es})
	c.sort_custom(func(a,b): return a.score<b.score)
	for i in range(min(20,c.size())): print_c("#"+str(i+1),c[i])
	quit()
