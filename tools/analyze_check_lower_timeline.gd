extends SceneTree

const PATH := "res://resources/animate/Kimodo/check_lower.res"
const FPS := 30.0
var important := {"Hips":3.0,"Spine":1.5,"Chest":1.5,"UpperChest":1.2,"Head":1.0,"LeftUpperLeg":2.0,"RightUpperLeg":2.0,"LeftUpperArm":1.0,"RightUpperArm":1.0,"LeftLowerArm":1.0,"RightLowerArm":1.0}
func bone_name(anim:Animation,i:int)->String:
	var p:=str(anim.track_get_path(i)); var idx:=p.rfind(":"); return p.substr(idx+1) if idx>=0 else p
func find_track(anim:Animation,name:String,typ:int)->int:
	for i in range(anim.get_track_count()):
		if anim.track_get_type(i)==typ and bone_name(anim,i)==name: return i
	return -1
func qdeg(a:Quaternion,b:Quaternion)->float:
	var d:float=abs(a.dot(b)); d=clamp(d,-1,1); return rad_to_deg(2*acos(d))
func pose_delta(anim:Animation,a:float,b:float)->float:
	var sum:=0.0; var ws:=0.0
	for i in range(anim.get_track_count()):
		if anim.track_get_type(i)!=Animation.TYPE_ROTATION_3D: continue
		var n:=bone_name(anim,i)
		if not important.has(n): continue
		var w:float=float(important[n]); sum+=qdeg(anim.rotation_track_interpolate(i,a), anim.rotation_track_interpolate(i,b))*w; ws+=w
	return sum/max(ws,0.0001)
func pos(anim:Animation,tr:int,t:float)->Vector3: return Vector3.ZERO if tr<0 else anim.position_track_interpolate(tr,t)
func _init():
	var anim:Animation=ResourceLoader.load(PATH,"Animation",ResourceLoader.CACHE_MODE_IGNORE)
	var root:=find_track(anim,"Root",Animation.TYPE_POSITION_3D); var hips:=find_track(anim,"Hips",Animation.TYPE_POSITION_3D)
	print("ANIM len=",anim.length," loop=",anim.loop_mode," root=",root," hips=",hips)
	for f in range(0,int(ceil(anim.length*FPS))+1):
		var t:float=min(float(f)/FPS,anim.length)
		if f%3!=0 and f!=int(ceil(anim.length*FPS)): continue
		var dt:float=1.0/FPS; var a:float=max(0,t-dt)
		var r:=pos(anim,root,t); var h:=pos(anim,hips,t); var pd:float=0.0 if t<=0 else pose_delta(anim,a,t)
		print("t=","%0.3f"%t," rootZ=","%0.4f"%r.z," hipsY=","%0.4f"%h.y," pose=","%0.3f"%pd)
	quit()
