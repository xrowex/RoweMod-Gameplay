"""UE 5.4 commandlet: import only the skeleton body in an isolated cook project."""
from pathlib import Path
import json
import unreal

ROOT=Path(__file__).resolve().parents[2]
assert Path(unreal.Paths.project_dir()).resolve()==(ROOT/'build/skeleton-ue').resolve(), 'Use the isolated skeleton cook project'
DEST='/Game/RoweMod/Characters/Skeleton'
tools=unreal.AssetToolsHelpers.get_asset_tools()
mgr=unreal.InterchangeManager.get_interchange_manager_scripted()
source=mgr.create_source_data(str(ROOT/'build/skeleton-source/SK_RoweSkeleton.gamebind.glb'))
params=unreal.ImportAssetParameters();params.replace_existing=True
mgr.import_asset(DEST,source,params)
paths=unreal.EditorAssetLibrary.list_assets(DEST,True,False)
meshes=[unreal.load_asset(p) for p in paths if p.split('.')[-1]=='SK_RoweSkeleton_gamebind' and isinstance(unreal.load_asset(p),unreal.SkeletalMesh)]
assert len(meshes)==1,paths
mesh=meshes[0]
if mesh.get_name()!='SK_RoweSkeleton':
    if unreal.EditorAssetLibrary.does_asset_exist(DEST+'/SK_RoweSkeleton'):
        unreal.EditorAssetLibrary.delete_asset(DEST+'/SK_RoweSkeleton')
    assert tools.rename_assets([unreal.AssetRenameData(mesh,DEST,'SK_RoweSkeleton')])
# These asset paths resolve to the original game's rig and ragdoll on load.
# The stand-in rig/physics packages are never included in the final mod.
rig_path='/Game/MainFolder/Character/body/main-rig/main-rig'
rig=unreal.load_asset(rig_path) or unreal.EditorAssetLibrary.duplicate_asset(mesh.skeleton.get_path_name(),rig_path)
assert rig
mesh.skeleton=rig
physics=mesh.get_editor_property('physics_asset')
if physics:
    physics_path='/Game/MainFolder/Character/body/main-rig/PA-RI-main'
    physics=unreal.load_asset(physics_path) or unreal.EditorAssetLibrary.duplicate_asset(physics.get_path_name(),physics_path)
    assert physics
    mesh.set_editor_property('physics_asset',physics)
else:
    raise RuntimeError('Import did not create a physics asset; cannot retain stock ragdoll reference')
mat=unreal.load_asset(DEST+'/M_Bone') or tools.create_asset('M_Bone',DEST,unreal.Material,unreal.MaterialFactoryNew())
mel=unreal.MaterialEditingLibrary
color=mel.create_material_expression(mat,unreal.MaterialExpressionConstant3Vector,0,0)
color.set_editor_property('constant',unreal.LinearColor(.72,.67,.53,1))
mel.connect_material_property(color,'',unreal.MaterialProperty.MP_BASE_COLOR)
rough=mel.create_material_expression(mat,unreal.MaterialExpressionConstant,0,160)
rough.set_editor_property('r',.64);mel.connect_material_property(rough,'',unreal.MaterialProperty.MP_ROUGHNESS)
mat.set_editor_property('used_with_skeletal_mesh',True)
mel.recompile_material(mat)
mi=unreal.load_asset(DEST+'/MI_Bone') or tools.create_asset('MI_Bone',DEST,unreal.MaterialInstanceConstant,unreal.MaterialInstanceConstantFactoryNew())
mel.set_material_instance_parent(mi,mat)
materials=list(mesh.get_editor_property('materials'))
assert len(materials)==4,'Reserved native material slots were lost during import'
for m in materials:m.set_editor_property('material_interface',mi)
mesh.materials=materials
thumbnail=unreal.AssetImportTask()
thumbnail.filename=str(ROOT/'build/skeleton-source/skeleton-preview.png')
thumbnail.destination_path=DEST
thumbnail.destination_name='T_SkeletonPreview'
thumbnail.automated=True
thumbnail.replace_existing=True
thumbnail.save=True
tools.import_asset_tasks([thumbnail])
texture=unreal.load_asset(DEST+'/T_SkeletonPreview')
assert isinstance(texture,unreal.Texture2D)
texture.set_editor_property('lod_group',unreal.TextureGroup.TEXTUREGROUP_UI)
texture.set_editor_property('mip_gen_settings',unreal.TextureMipGenSettings.TMGS_NO_MIPMAPS)
unreal.EditorAssetLibrary.save_directory('/Game',False,True)
report={'mesh':mesh.get_path_name(),'skeleton':rig.get_path_name(),'physics':physics.get_path_name(),'material_slots':len(materials)}
(ROOT/'build/skeleton-source/unreal-import.json').write_text(json.dumps(report,indent=2))
unreal.log('ROWE_SKELETON_IMPORTED '+json.dumps(report))
