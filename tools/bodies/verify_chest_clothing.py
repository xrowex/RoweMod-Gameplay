"""Offline deformation checks against the extracted hoodie (not a game test)."""
import json, math
from pathlib import Path
import bpy
from mathutils import Quaternion, Vector
from mathutils.bvhtree import BVHTree

ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'build/skeleton-source'
HOODIE=ROOT/'build/skeleton-reference/RollerSkate/Content/MainFolder/Character/upper/hoodie/hoodie-male.glb'
POSES={
    'neutral':{},
    'forward_lean':{'spine_02':(0,0,15),'spine_03':(0,0,15)},
    'back_lean':{'spine_02':(0,0,-10),'spine_03':(0,0,-10)},
    'turn':{'spine_02':(0,15,0),'spine_04':(0,20,0)},
    'side_bend':{'spine_02':(12,0,0),'spine_04':(12,0,0)},
}

def check(blend):
    bpy.ops.wm.open_mainfile(filepath=str(blend))
    mesh=bpy.data.objects['SK_RoweSkeleton']
    arm=next(o for o in bpy.data.objects if o.type=='ARMATURE')
    indices=[v.index for v in mesh.data.vertices if 1.07<v.co.z<1.43 and v.co.y<0 and abs(v.co.x)<.18
             and any(mesh.vertex_groups[g.group].name.startswith('spine_') for g in v.groups)]
    assert len(indices)>1000
    before=set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(HOODIE),bone_heuristic='TEMPERANCE')
    hoodie=max((o for o in set(bpy.data.objects)-before if o.type=='MESH'),key=lambda o:len(o.data.vertices))
    world=hoodie.matrix_world.copy();hoodie.parent=arm;hoodie.matrix_world=world
    for modifier in hoodie.modifiers:
        if modifier.type=='ARMATURE':modifier.object=arm
    results={}
    for name,rotations in POSES.items():
        for bone in arm.pose.bones:
            bone.rotation_mode='QUATERNION';bone.rotation_quaternion=Quaternion()
        for name_bone,degrees in rotations.items():
            bone=arm.pose.bones[name_bone]
            # Apply model-space bend axes, converting into each native joint's
            # local rest axes rather than assuming an exported bone orientation.
            q=Quaternion()
            for axis,angle in zip(((0,0,1),(0,1,0),(1,0,0)),degrees):
                local=bone.bone.matrix_local.to_quaternion().inverted() @ Vector(axis)
                q=q @ Quaternion(local,math.radians(angle))
            bone.rotation_quaternion=q
        bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
        evaluated=hoodie.evaluated_get(deps);cloth=evaluated.to_mesh();cloth.calc_loop_triangles()
        vertices=[evaluated.matrix_world@v.co for v in cloth.vertices]
        tree=BVHTree.FromPolygons(vertices,[tuple(t.vertices) for t in cloth.loop_triangles],all_triangles=True)
        current=mesh.evaluated_get(deps);bones=current.to_mesh()
        distances=[];details=[];front_distances=[];openings=0
        for i in indices:
            p=current.matrix_world@bones.vertices[i].co
            hit,normal,_,_=tree.find_nearest(p)
            distances.append((p-hit).dot(normal))
            # A hoodie is open at its collar/hem: nearest-triangle normals do
            # not define a closed volume there. Measure actual front coverage.
            front,front_normal,_,_=tree.ray_cast(Vector((p.x,-2,p.z)),Vector((0,1,0)),4)
            if front is not None and front_normal.y<-.1:
                front_distances.append(front.y-p.y)
            else:openings+=1
            details.append({'rest':list(mesh.data.vertices[i].co),'distance':distances[-1],
                            'weights':{mesh.vertex_groups[g.group].name:g.weight for g in mesh.data.vertices[i].groups}})
        results[name]={'sampled_vertices':len(indices),'outside_over_1mm':sum(d>.001 for d in distances),
                       'maximum_signed_distance_m':max(distances),
                       'worst_vertices':sorted(details,key=lambda x:x['distance'],reverse=True)[:5],
                       'front_protrusions_over_1mm':sum(d>.001 for d in front_distances),
                       'maximum_front_protrusion_m':max(front_distances),
                       'open_collar_or_uncovered_samples':openings}
        current.to_mesh_clear();evaluated.to_mesh_clear()
    return results

report={'scope':'Offline hoodie deformation check; native animations still require in-game testing',
        'before':check(SOURCE/'ChestFitBefore.blend'),'after':check(SOURCE/'RoweSkeleton.blend')}
(SOURCE/'chest-clothing-check.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
assert all(p['front_protrusions_over_1mm']==0 for p in report['after'].values()),'Chest still protrudes through the hoodie front'
