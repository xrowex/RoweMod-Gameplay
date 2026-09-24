"""Restore native bone axes after Blender export; run in Blender's Python.

Use a fresh CUE4Parse Gltf2 export, not a Blender-resaved reference. Cooked
bone transforms must also pass verify_boot_pose.py before packaging.
"""
import json
import struct
from pathlib import Path
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[2]
REFERENCE = ROOT/'build/skeleton-reference/RollerSkate/Content/MainFolder/Character/body/male/male-01/male-body-01.glb'
OUT = ROOT/'build/skeleton-source'

def read(path):
    raw=path.read_bytes()
    assert raw[:4]==b'glTF'
    length=struct.unpack_from('<I',raw,12)[0]
    doc=json.loads(raw[20:20+length])
    start=20+length
    size,kind=struct.unpack_from('<I4s',raw,start)
    assert kind==b'BIN\0'
    return doc,raw[start+8:start+8+size]

def write(path,doc,blob):
    js=json.dumps(doc,separators=(',',':')).encode()
    js+=b' '*(-len(js)%4);blob+=b'\0'*(-len(blob)%4)
    path.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(js)+len(blob))+
                    struct.pack('<I4s',len(js),b'JSON')+js+
                    struct.pack('<I4s',len(blob),b'BIN\0')+blob)

def main():
    doc,blob=read(OUT/'SK_RoweSkeleton.glb');ref,_=read(REFERENCE)
    assert len(doc['skins'])==len(ref['skins'])==1
    nodes=doc['nodes'];skin=doc['skins'][0]
    originals={ref['nodes'][i]['name']:ref['nodes'][i] for i in ref['skins'][0]['joints']}
    assert {nodes[i]['name'] for i in skin['joints']}==set(originals)
    def parents(d):
        return {child:i for i,n in enumerate(d['nodes']) for child in n.get('children',[])}
    def hierarchy(d):
        p=parents(d);j=set(d['skins'][0]['joints'])
        return {d['nodes'][i]['name']:d['nodes'][p[i]]['name'] if p.get(i) in j else None for i in j}
    assert hierarchy(doc)==hierarchy(ref)
    for i in skin['joints']:
        node=nodes[i];original=originals[node['name']]
        node.pop('matrix',None)
        for key,default in [('rotation',[0,0,0,1]),('translation',[0,0,0]),('scale',[1,1,1])]:
            node[key]=original.get(key,default)
    ancestry=parents(doc);cache={}
    def world(i):
        if i not in cache:
            n=nodes[i]
            if 'matrix' in n:
                m=Matrix([n['matrix'][k:k+4] for k in range(0,16,4)]).transposed()
            else:
                x,y,z,w=n.get('rotation',[0,0,0,1])
                m=Matrix.LocRotScale(Vector(n.get('translation',[0,0,0])),Quaternion((w,x,y,z)),Vector(n.get('scale',[1,1,1])))
            cache[i]=world(ancestry[i])@m if i in ancestry else m
        return cache[i]
    values=[]
    for i in skin['joints']:
        inverse=world(i).inverted()
        values.extend(inverse[row][col] for col in range(4) for row in range(4))
    blob+=b'\0'*(-len(blob)%4);offset=len(blob)
    blob+=struct.pack('<'+'f'*len(values),*values)
    view=len(doc['bufferViews'])
    doc['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':len(values)*4})
    skin['inverseBindMatrices']=len(doc['accessors'])
    doc['accessors'].append({'bufferView':view,'componentType':5126,'count':len(skin['joints']),'type':'MAT4'})
    doc['buffers'][0]['byteLength']=len(blob)
    write(OUT/'SK_RoweSkeleton.gamebind.glb',doc,blob)
    print('NATIVE_BIND_RESTORED',len(skin['joints']))

if __name__=='__main__':main()
