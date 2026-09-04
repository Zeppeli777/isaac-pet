using System.IO;
using IsaacPet.Windows.Sprites;

namespace IsaacPet.Windows.Core;

public enum PetAppearanceID
{
    Isaac,
    Magdalene,
    Judas,
}

public sealed record PetAppearanceDefinition(
    PetAppearanceID Id,
    string DisplayName,
    string SpriteSheetName,
    string? Subdirectory);

public static class PetAppearanceCatalog
{
    public static readonly IReadOnlyList<PetAppearanceDefinition> Definitions =
    [
        new(PetAppearanceID.Isaac, "Isaac（默认）", "spritesheet", null),
        new(PetAppearanceID.Magdalene, "Magdalene", "magdalene-spritesheet", "Agents"),
        new(PetAppearanceID.Judas, "Judas", "judas-spritesheet", "Agents"),
    ];

    public static PetAppearanceDefinition DefinitionFor(PetAppearanceID id) =>
        Definitions.First(d => d.Id == id);

    public static PetAppearanceID Parse(string? rawValue) => rawValue switch
    {
        "magdalene" => PetAppearanceID.Magdalene,
        "judas" => PetAppearanceID.Judas,
        _ => PetAppearanceID.Isaac,
    };

    public static string RawValue(PetAppearanceID id) => id switch
    {
        PetAppearanceID.Magdalene => "magdalene",
        PetAppearanceID.Judas => "judas",
        _ => "isaac",
    };

    public static string? SheetPath(PetAppearanceDefinition definition)
    {
        var directory = definition.Subdirectory == null
            ? SpriteAtlas.AssetsDirectory
            : Path.Combine(SpriteAtlas.AssetsDirectory, definition.Subdirectory);
        var path = Path.Combine(directory, definition.SpriteSheetName + ".png");
        return File.Exists(path) ? path : null;
    }

    public static (bool IsAvailable, string UnavailableReason) Availability(PetAppearanceID id)
    {
        var definition = DefinitionFor(id);
        if (SheetPath(definition) == null)
        {
            return (false, "角色图集尚未安装；生成并通过 QA 后会自动启用。");
        }
        return (true, "");
    }
}
