using UAssetAPI;
using UAssetAPI.ExportTypes;
using UAssetAPI.PropertyTypes.Objects;
using UAssetAPI.UnrealTypes;
using UAssetAPI.Unversioned;

// Route existing table-patcher logic into our isolated staging root. Never
// clear or overwrite the clothing project's current patched tables.
if (args.Length != 2) throw new ArgumentException("Expected staging root and item JSON");
var root = Path.GetFullPath(args[0]);
if (!File.Exists(Path.Combine(root, ".rowemod-skeleton-staging")))
    throw new InvalidOperationException("Missing isolated skeleton staging marker");
var result = DtPatcher.Program.Run(new[] { "--item", Path.GetFullPath(args[1]) }, root);
if (result != 0) return result;
var output = Path.Combine(root, "dumps", "patched", "DT-bodytypes.uasset");
var asset = new UAsset(output, EngineVersion.VER_UE5_4,
    new Usmap(Path.Combine(root, "dumps", "mappings.usmap")));
var table = asset.Exports.OfType<DataTableExport>().Single();
var row = table.Table.Data.Single(r => r.Name.ToString() == "rowe-skeleton-mod");
var label = row.Value.OfType<TextPropertyData>()
    .Single(p => p.Name.ToString().StartsWith("LocalizedName_"));
// A cloned FText must not share the stock Male 1 localization identity.
label.Namespace = new FString("RoweMod.Bodies");
asset.Write(output);
return 0;
