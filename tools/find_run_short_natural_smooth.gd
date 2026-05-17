extends SceneTree

const SRC_PATH := "res://resources/animate/Kimodo/run_forward_loop.res"
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
	var d:float=abs(a.dot(b)); d=clamp(d,-1,1); return rad_to_deg(2.0*acos(d))
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
func root_z(anim:Animation,rt:int,t:float)->float: return anim.position_track_interpolate(rt,t).z
func local_delta(anim:Animation,t0:float,t1:float)->float:
	return pose_score(anim,t0,t1).score
func _init():
	var anim:Animation=ResourceLoader.load(SRC_PATH)
	var rt:=root_track(anim)
	var dt:=1.0/FPS
	var c:=[]
	# 稳定跑步段大概 1.6s 后，搜索 0.75~0.95s 的单周期。
	for sf in range(int(round(1.55*FPS)), int(round(3.25*FPS))+1):
		var s:float=float(sf)/FPS
		for df in range(int(round(0.75*FPS)), int(round(0.95*FPS))+1):
			var dur:float=float(df)/FPS
			var e:float=s+dur
			if e>4.2: continue
			var gap:=pose_score(anim,s,e)
			var prev:float=local_delta(anim,e-dt,e)
			var next:float=local_delta(anim,s,s+dt)
			var rz:float=root_z(anim,rt,e)-root_z(anim,rt,s)
			var sp:float=rz/dur
			if sp<2.0 or sp>2.8: continue
			# 重点：首尾姿态接近 + 接缝前后速度/变化量接近，不追求强行 0 gap。
			var seam_balance:float=abs(prev-next)
			var seam_energy:float=max(prev,next)
			var score:float=gap.score*1.4 + seam_balance*1.1 + seam_energy*0.12 + abs(sp-2.4)*0.25
			c.append({"s":s,"e":e,"dur":dur,"score":score,"gap":gap.score,"max":gap.max,"max_name":gap.max_name,"prev":prev,"next":next,"balance":seam_balance,"rootZ":rz,"speed":sp})
	c.sort_custom(func(a,b): return a.score<b.score)
	print("BEST natural run loop candidates")
	for i in range(min(20,c.size())):
		var d=c[i]
		print("#",i+1," s=","%0.4f"%d.s," e=","%0.4f"%d.e," dur=","%0.4f"%d.dur," score=","%0.3f"%d.score," gap=","%0.3f"%d.gap," max=","%0.2f"%d.max,"@",d.max_name," prev=","%0.3f"%d.prev," next=","%0.3f"%d.next," bal=","%0.3f"%d.balance," speed=","%0.3f"%d.speed," rootZ=","%0.4f"%d.rootZ)
	quit()
