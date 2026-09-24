"""Inspect the anatomical source and the existing Rollout body rig in Blender."""
import json
from pathlib import Path
import bpy
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build/skeleton-source'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(OUT/'SkeletalSystem100.fbx'),use_anim=False)
meshes=[]
for obj in bpy.data.objects:
    if obj.type!='MESH': continue
    points=[obj.matrix_world @ Vector(c) for c in obj.bound_box]
    meshes.append(dict(name=obj.name,vertices=len(obj.data.vertices),faces=len(obj.data.polygons),
        min=[min(p[i] for p in points) for i in range(3)],max=[max(p[i] for p in points) for i in range(3)]))
(OUT/'anatomy-inventory.json').write_text(json.dumps(meshes,indent=2))
print('ANATOMY',len(meshes),'meshes',sum(x['faces'] for x in meshes),'faces')
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(ROOT/'build/skeleton-reference/RollerSkate/Content/MainFolder/Character/body/male/male-01/male-body-01.glb'),bone_heuristic='TEMPERANCE')
arm=next(o for o in bpy.data.objects if o.type=='ARMATURE')
bones={b.name:dict(head=list(arm.matrix_world @ b.head_local),tail=list(arm.matrix_world @ b.tail_local)) for b in arm.data.bones}
(OUT/'rollout-rig.json').write_text(json.dumps(bones,indent=2))
print('RIG',len(bones),'bones')
