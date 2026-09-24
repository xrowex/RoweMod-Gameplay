"""Fit the ribcage inside the stock torso and share its skinning weights."""
import math
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def fit_chest(parts, body):
    body.data.calc_loop_triangles()
    positions=[body.matrix_world @ v.co for v in body.data.vertices]
    triangles=[tuple(t.vertices) for t in body.data.loop_triangles]
    surface=BVHTree.FromPolygons(positions,triangles,all_triangles=True)
    weights=[{body.vertex_groups[g.group].name:g.weight for g in v.groups} for v in body.data.vertices]
    margin=.014
    step=.01
    samples=[]
    factors={}
    before=0.0
    for obj in parts:
        for v in obj.data.vertices:
            p=v.co.copy()
            # Leave shoulders alone; only ribs, cartilage and sternum are fitted.
            p.x*=.92
            front,_,_,_=surface.ray_cast(Vector((p.x,-1,p.z)),Vector((0,1,0)),2)
            back,_,_,_=surface.ray_cast(Vector((p.x,1,p.z)),Vector((0,-1,0)),2)
            if front is None or back is None or back.y-front.y < margin*3:
                raise RuntimeError('Chest vertex is outside the stock torso cross-section')
            anchor=back.y-margin
            factor=min(1.0,(front.y+margin-anchor)/(p.y-anchor)) if p.y<anchor else 1.0
            factor=max(.05,factor)
            band=math.floor(p.z/step)
            factors[band]=min(factors.get(band,1),factor)
            samples.append((obj,v,p,anchor,band))
            before=max(before,front.y-p.y)
    # Use the most conservative adjacent slice. Interpolating this profile
    # avoids hard slice boundaries while retaining a margin under tight tops.
    safe={i:min(factors.get(j,1) for j in range(i-2,i+3)) for i in factors}
    after=1.0
    influence_names=set()
    for obj,v,p,anchor,band in samples:
        t=p.z/step-band
        factor=safe[band]*(1-t)+safe.get(band+1,safe[band])*t
        p.y=anchor+(p.y-anchor)*factor
        v.co=p
        front,_,_,_=surface.ray_cast(Vector((p.x,-1,p.z)),Vector((0,1,0)),2)
        after=min(after,p.y-front.y)
        nearest,_,index,_=surface.find_nearest(p)
        ids=triangles[index];a,b,c=(positions[i] for i in ids)
        ab=b-a;ac=c-a;ap=nearest-a
        d00=ab.dot(ab);d01=ab.dot(ac);d11=ac.dot(ac)
        denom=d00*d11-d01*d01
        if abs(denom)<1e-15:
            bary=(1,0,0)
        else:
            vb=(d11*ap.dot(ab)-d01*ap.dot(ac))/denom
            vc=(d00*ap.dot(ac)-d01*ap.dot(ab))/denom
            bary=(1-vb-vc,vb,vc)
        blended={}
        for vid,w in zip(ids,bary):
            for name,value in weights[vid].items():
                blended[name]=blended.get(name,0)+max(0,w)*value
        influences=sorted(blended.items(),key=lambda x:x[1],reverse=True)[:4]
        total=sum(w for _,w in influences)
        assert total>0
        for old in list(v.groups):obj.vertex_groups[old.group].remove([v.index])
        for name,w in influences:
            if w<=1e-6:continue
            group=obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
            group.add([v.index],w/total,'REPLACE')
            influence_names.add(name)
    assert after>=margin-.0001, f'Chest clearance lost: {after}'
    return {'vertices':len(samples),'minimum_front_clearance_m':after,
            'previous_front_protrusion_m':before,'spine_weights':sorted(influence_names)}
