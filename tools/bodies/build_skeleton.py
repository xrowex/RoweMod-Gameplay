"""Fit Z-Anatomy's bone surfaces to Rollout's exact extracted body rig.

Run with Blender --background --factory-startup --python this-file.
Source asset attribution: docs/licenses/Skeleton.txt (CC BY-SA).
"""
import json, math, re, sys
from pathlib import Path
import bpy
from mathutils import Vector, Matrix

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build/skeleton-source'
REFERENCE=ROOT/'build/skeleton-reference/RollerSkate/Content/MainFolder/Character/body/male/male-01/male-body-01.glb'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(OUT/'SkeletalSystem100.fbx'),use_anim=False)
anatomy=[o for o in bpy.data.objects if o.type=='MESH']
before_reference=set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(REFERENCE),bone_heuristic='TEMPERANCE')
body=max((o for o in set(bpy.data.objects)-before_reference if o.type=='MESH'),key=lambda o:len(o.data.vertices))
arm=next(o for o in bpy.data.objects if o.type=='ARMATURE')
arm.name='main-rig'
heads={b.name:arm.matrix_world @ b.head_local for b in arm.data.bones}
def segment(p,a,b,c,d):
    a,b,c,d=map(Vector,(a,b,c,d))
    v=b-a;w=d-c;q=v.rotation_difference(w)
    # Match joint spacing while retaining the width of the anatomical bone.
    t=(p-a).dot(v)/v.length_squared
    return c+w*t+q@((p-a)-v*t)
def torso(p):
    return Vector((p.x*1.05,p.y-.040, .866+(p.z-.87)*1.07))
def skull(p):
    return Vector((p.x,p.y-.025,1.548+(p.z-1.53)))
fingers={'first':'thumb','second':'index','third':'middle','fourth':'ring','fifth':'pinky'}
head_names={'Frontal bone','Ethmoid bone','Occipital bone','Sphenoid bone','Mandible','Vomer',
    'Maxilla','Parietal bone','Temporal bone','Zygomatic bone','Nasal bone','Lacrimal bone',
    'Palatine bone','Inferior nasal concha bone','Hyoid bone'}
wrist_names={'Scaphoid bone','Lunate bone','Triquetrum bone','Pisiform bone','Trapezium bone',
    'Trapezoid bone','Capitate bone','Hamate bone'}
foot_names={'Calcaneus','Talus','Navicular bone','Cuboid bone','Medial cuneiform bone',
    'Intermediate cuneiform bone','Lateral cuneiform bone','Sesamoid bones of foot'}
kept=[];inventory=[];chest=[]
for obj in anatomy:
    name=obj.name;base=re.sub(r'\.[lr]$','',name);side=name[-1] if name.endswith(('.l','.r')) else None
    if len(obj.data.polygons)<20: continue
    sign=1 if side=='l' else -1
    shoulder=(sign*.169,.025,1.385);elbow=(sign*.235,.030,1.10);wrist=(sign*.256,-.015,.858)
    hip=(sign*.096,.025,.865);knee=(sign*.084,.025,.431);ankle=(sign*.063,.011,.080)
    bone=None;transform=torso;is_chest=False
    if base in head_names or re.fullmatch(r'(Upper|Lower) (canine|first molar tooth|second molar tooth|first premolar|second premolar|lateral incisor|medial incisor)',base):
        bone='head';transform=skull
    elif base in ('Hip bone','Sacrum','Coccyx'): bone='pelvis'
    elif base in ('Body of sternum','Manubrium of sternum','Xiphoid process') or re.fullmatch(r'(?:Costal cartilage of )?\w+ rib',base):
        bone='spine_04';is_chest=True
    elif base.startswith('Vertebra ') or base in ('Atlas (C1)','Axis (C2)'):
        center=sum((obj.matrix_world@Vector(c) for c in obj.bound_box),Vector())/8
        bone=min(['spine_01','spine_02','spine_03','spine_04','spine_05','neck_01','neck_02'],key=lambda b:abs(heads[b].z-torso(center).z))
    elif side and base in ('Clavicle','Scapula'):
        bone='clavicle_'+side
        transform=lambda p:segment(p,(sign*.035,.025,1.40),shoulder,heads[bone],heads['upperarm_'+side])
    elif side and base=='Humerus':
        bone='upperarm_'+side;transform=lambda p:segment(p,shoulder,elbow,heads[bone],heads['lowerarm_'+side])
    elif side and base in ('Ulna','Radius'):
        bone='lowerarm_'+side;transform=lambda p:segment(p,elbow,wrist,heads[bone],heads['hand_'+side])
    elif side and base=='Femur':
        bone='thigh_'+side;transform=lambda p:segment(p,hip,knee,heads[bone],heads['calf_'+side])
    elif side and base in ('Tibia','Fibula','Patella'):
        bone='calf_'+side;transform=lambda p:segment(p,knee,ankle,heads[bone],heads['foot_'+side])
    elif side and (base in foot_names or 'of foot' in base or 'metatarsal bone' in base):
        bone='foot_'+side
        transform=lambda p:segment(p,ankle,(sign*.075,-.135,.020),heads[bone],heads['ball_'+side])
    elif side and base in wrist_names:
        bone='hand_'+side
        transform=lambda p:segment(p,wrist,(sign*.270,-.025,.833),heads[bone],heads['middle_metacarpal_'+side])
    elif side and ('finger of hand' in base or 'metacarpal bone' in base):
        digit=next((v for k,v in fingers.items() if k in base.lower()),None)
        if not digit: continue
        stage='metacarpal' if 'metacarpal' in base else {'Proximal':'01','Middle':'02','Distal':'03'}[base.split()[0]]
        if digit=='thumb': stage={'metacarpal':'01','01':'02','03':'03'}[stage]
        bone=digit+'_'+stage+'_'+side
        # Each anatomical phalanx remains rigid and follows its real game joint.
        points=[obj.matrix_world@v.co for v in obj.data.vertices]
        top=max(p.z for p in points);bottom=min(p.z for p in points)
        center=sum(points,Vector())/len(points)
        a=Vector((center.x,center.y,top));b=Vector((center.x,center.y,bottom))
        child={'metacarpal':'01','01':'02','02':'03'}.get(stage)
        target=heads[digit+'_'+child+'_'+side] if child else heads[bone]+(heads[bone]-heads[digit+'_02_'+side])*.75
        transform=lambda p:segment(p,a,b,heads[bone],target)
    if not bone: continue
    obj.data=obj.data.copy()
    world=obj.matrix_world.copy()
    for v in obj.data.vertices: v.co=transform(world@v.co)
    obj.parent=None;obj.matrix_world=Matrix.Identity(4)
    obj.vertex_groups.clear();group=obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))),1,'REPLACE')
    # Keep tiny finger geometry; reduce large skull/rib/scapula meshes.
    faces=len(obj.data.polygons)
    if faces>500:
        bpy.context.view_layer.objects.active=obj
        dec=obj.modifiers.new('Game detail','DECIMATE');dec.ratio=max(.03,min(1,300/faces))
        bpy.ops.object.modifier_apply(modifier=dec.name)
    kept.append(obj);inventory.append({'source':name,'bone':bone,'faces':len(obj.data.polygons)})
    if is_chest:chest.append(obj)
assert len(kept)>190, len(kept)
sys.path.insert(0,str(Path(__file__).resolve().parent))
from chest_fit import fit_chest
chest_report=fit_chest(chest,body)
(OUT/'chest-fit.json').write_text(json.dumps(chest_report,indent=2))
print('CHEST_FIT',json.dumps(chest_report))
for obj in list(bpy.data.objects):
    if obj not in kept and obj!=arm: bpy.data.objects.remove(obj,do_unlink=True)
bone_mat=bpy.data.materials.new('M_RoweSkeleton');bone_mat.diffuse_color=(.72,.67,.53,1);bone_mat.use_nodes=True
bsdf=bone_mat.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Base Color'].default_value=(.72,.67,.53,1);bsdf.inputs['Roughness'].default_value=.64
for obj in kept:
    obj.data.materials.clear();obj.data.materials.append(bone_mat)
    for p in obj.data.polygons:p.use_smooth=True;p.material_index=0
bpy.ops.object.select_all(action='DESELECT')
for obj in kept:obj.select_set(True)
bpy.context.view_layer.objects.active=kept[0];bpy.ops.object.join()
mesh=bpy.context.object;mesh.name='SK_RoweSkeleton';mesh.data.name=mesh.name
mesh.data.validate();mesh.data.update()
mesh.parent=arm;modifier=mesh.modifiers.new('Rollout rig','ARMATURE');modifier.object=arm
# Native body loading writes slots 0..2; real bone surfaces use slot 3.
mesh.data.materials.clear()
for i in range(3):
    placeholder=bpy.data.materials.new('ReservedBodySlot'+str(i));placeholder.diffuse_color=(0,0,0,1)
    mesh.data.materials.append(placeholder)
mesh.data.materials.append(bone_mat)
for poly in mesh.data.polygons:poly.material_index=3
# Preserve reserved material slots through glTF/Interchange using microscopic
# triangles inside the pelvis. Unused slots would be stripped on import.
import bmesh
bm=bmesh.new();bm.from_mesh(mesh.data)
for i in range(3):
    p=heads['pelvis']+Vector((i*.00001,0,0))
    verts=[bm.verts.new(p+Vector(v)) for v in ((0,0,0),(.000001,0,0),(0,.000001,0))]
    face=bm.faces.new(verts);face.material_index=i
bm.to_mesh(mesh.data);bm.free()
pelvis_group=mesh.vertex_groups.get('pelvis') or mesh.vertex_groups.new(name='pelvis')
for v in mesh.data.vertices:
    if not v.groups:pelvis_group.add([v.index],1,'REPLACE')
mesh.select_set(True);arm.select_set(True)
bpy.context.view_layer.objects.active=arm
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'RoweSkeleton.blend'))
bpy.ops.export_scene.gltf(filepath=str(OUT/'SK_RoweSkeleton.glb'),use_selection=True,export_format='GLB',export_animations=False,export_skins=True,export_yup=True)
(OUT/'adaptation.json').write_text(json.dumps({'parts':inventory,'vertices':len(mesh.data.vertices),'triangles':sum(len(p.vertices)-2 for p in mesh.data.polygons),'rig_bones':len(arm.data.bones)},indent=2))
print('SKELETON_BUILT',len(kept),'parts',len(mesh.data.vertices),'vertices')
# Render the actual adapted mesh for visual QA, without running the game.
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
scene.render.resolution_x=720;scene.render.resolution_y=900;scene.render.resolution_percentage=100
scene.world=bpy.data.worlds.new('Preview world');scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.055,.065,.085,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value=.5
for loc,energy,size in [((2,-3,4),420,3),((-2,-1,2),180,2),((0,2,3),300,2)]:
    bpy.ops.object.light_add(type='AREA',location=loc);light=bpy.context.object;light.data.energy=energy;light.data.shape='DISK';light.data.size=size
    light.rotation_euler=(Vector((0,0,1))-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(2.5,-5,2.2));camera=bpy.context.object
camera.rotation_euler=(Vector((0,0,.9))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=2.05
scene.camera=camera;scene.render.filepath=str(OUT/'skeleton-preview.png')
bpy.ops.render.render(write_still=True)
