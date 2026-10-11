using System.IO;
using IsaacPet.Windows.Sprites;

namespace IsaacPet.Windows.Core;

public enum PetAppearanceID
{
    Isaac,
    Magdalene,
    Cain,
    Judas,
    BlueBaby,
    Eve,
    Samson,
    Azazel,
    Lazarus,
    Eden,
    TheLost,
    Lilith,
    Keeper,
    Apollyon,
    TheForgotten,
    Bethany,
    JacobEsau,
}

public sealed record PetAppearanceDefinition(
    PetAppearanceID Id,
    string DisplayName,
    string PersonaName,
    string SpriteSheetName,
    string? Subdirectory,
    string? ShootingAtlasName = null,
    string? VerticalWalkingName = null,
    string? RaisingAtlasName = null);

public static class PetAppearanceCatalog
{
    public static readonly IReadOnlyList<PetAppearanceDefinition> Definitions =
    [
        new(PetAppearanceID.Isaac, "Isaac（默认）", "Isaac", "spritesheet", null),
        new(PetAppearanceID.Magdalene, "Magdalene", "Magdalene", "magdalene-spritesheet", "Agents",
            ShootingAtlasName: "magdalene-shooting-atlas",
            VerticalWalkingName: "magdalene-walking-vertical-atlas",
            RaisingAtlasName: "magdalene-raising-atlas"),
        new(PetAppearanceID.Cain, "Cain", "Cain", "cain-spritesheet", "Agents",
            ShootingAtlasName: "cain-shooting-atlas",
            VerticalWalkingName: "cain-walking-vertical-atlas",
            RaisingAtlasName: "cain-raising-atlas"),
        new(PetAppearanceID.Judas, "Judas", "Judas", "judas-spritesheet", "Agents",
            ShootingAtlasName: "judas-shooting-atlas",
            VerticalWalkingName: "judas-walking-vertical-atlas",
            RaisingAtlasName: "judas-raising-atlas"),
        new(PetAppearanceID.BlueBaby, "Blue Baby（???）", "Blue Baby", "bluebaby-spritesheet", "Agents",
            ShootingAtlasName: "bluebaby-shooting-atlas",
            VerticalWalkingName: "bluebaby-walking-vertical-atlas",
            RaisingAtlasName: "bluebaby-raising-atlas"),
        new(PetAppearanceID.Eve, "Eve", "Eve", "eve-spritesheet", "Agents",
            ShootingAtlasName: "eve-shooting-atlas",
            VerticalWalkingName: "eve-walking-vertical-atlas",
            RaisingAtlasName: "eve-raising-atlas"),
        new(PetAppearanceID.Samson, "Samson", "Samson", "samson-spritesheet", "Agents",
            ShootingAtlasName: "samson-shooting-atlas",
            VerticalWalkingName: "samson-walking-vertical-atlas",
            RaisingAtlasName: "samson-raising-atlas"),
        new(PetAppearanceID.Azazel, "Azazel", "Azazel", "azazel-spritesheet", "Agents",
            ShootingAtlasName: "azazel-shooting-atlas",
            VerticalWalkingName: "azazel-walking-vertical-atlas",
            RaisingAtlasName: "azazel-raising-atlas"),
        new(PetAppearanceID.Lazarus, "Lazarus", "Lazarus", "lazarus-spritesheet", "Agents",
            ShootingAtlasName: "lazarus-shooting-atlas",
            VerticalWalkingName: "lazarus-walking-vertical-atlas",
            RaisingAtlasName: "lazarus-raising-atlas"),
        new(PetAppearanceID.Eden, "Eden", "Eden", "eden-spritesheet", "Agents",
            ShootingAtlasName: "eden-shooting-atlas",
            VerticalWalkingName: "eden-walking-vertical-atlas",
            RaisingAtlasName: "eden-raising-atlas"),
        new(PetAppearanceID.TheLost, "The Lost", "The Lost", "thelost-spritesheet", "Agents",
            ShootingAtlasName: "thelost-shooting-atlas",
            VerticalWalkingName: "thelost-walking-vertical-atlas",
            RaisingAtlasName: "thelost-raising-atlas"),
        new(PetAppearanceID.Lilith, "Lilith", "Lilith", "lilith-spritesheet", "Agents",
            ShootingAtlasName: "lilith-shooting-atlas",
            VerticalWalkingName: "lilith-walking-vertical-atlas",
            RaisingAtlasName: "lilith-raising-atlas"),
        new(PetAppearanceID.Keeper, "Keeper", "Keeper", "keeper-spritesheet", "Agents",
            ShootingAtlasName: "keeper-shooting-atlas",
            VerticalWalkingName: "keeper-walking-vertical-atlas",
            RaisingAtlasName: "keeper-raising-atlas"),
        new(PetAppearanceID.Apollyon, "Apollyon", "Apollyon", "apollyon-spritesheet", "Agents",
            ShootingAtlasName: "apollyon-shooting-atlas",
            VerticalWalkingName: "apollyon-walking-vertical-atlas",
            RaisingAtlasName: "apollyon-raising-atlas"),
        new(PetAppearanceID.TheForgotten, "The Forgotten", "The Forgotten", "theforgotten-spritesheet", "Agents",
            ShootingAtlasName: "theforgotten-shooting-atlas",
            VerticalWalkingName: "theforgotten-walking-vertical-atlas",
            RaisingAtlasName: "theforgotten-raising-atlas"),
        new(PetAppearanceID.Bethany, "Bethany", "Bethany", "bethany-spritesheet", "Agents",
            ShootingAtlasName: "bethany-shooting-atlas",
            VerticalWalkingName: "bethany-walking-vertical-atlas",
            RaisingAtlasName: "bethany-raising-atlas"),
        new(PetAppearanceID.JacobEsau, "Jacob & Esau", "Jacob & Esau", "jacobesau-spritesheet", "Agents",
            ShootingAtlasName: "jacobesau-shooting-atlas",
            VerticalWalkingName: "jacobesau-walking-vertical-atlas",
            RaisingAtlasName: "jacobesau-raising-atlas"),
    ];

    public static PetAppearanceDefinition DefinitionFor(PetAppearanceID id) =>
        Definitions.First(d => d.Id == id);

    public static PetAppearanceID Parse(string? rawValue) => rawValue switch
    {
        "magdalene" => PetAppearanceID.Magdalene,
        "cain" => PetAppearanceID.Cain,
        "judas" => PetAppearanceID.Judas,
        "bluebaby" => PetAppearanceID.BlueBaby,
        "eve" => PetAppearanceID.Eve,
        "samson" => PetAppearanceID.Samson,
        "azazel" => PetAppearanceID.Azazel,
        "lazarus" => PetAppearanceID.Lazarus,
        "eden" => PetAppearanceID.Eden,
        "thelost" => PetAppearanceID.TheLost,
        "lilith" => PetAppearanceID.Lilith,
        "keeper" => PetAppearanceID.Keeper,
        "apollyon" => PetAppearanceID.Apollyon,
        "theforgotten" => PetAppearanceID.TheForgotten,
        "bethany" => PetAppearanceID.Bethany,
        "jacobesau" => PetAppearanceID.JacobEsau,
        _ => PetAppearanceID.Isaac,
    };

    public static string RawValue(PetAppearanceID id) => id switch
    {
        PetAppearanceID.Magdalene => "magdalene",
        PetAppearanceID.Cain => "cain",
        PetAppearanceID.Judas => "judas",
        PetAppearanceID.BlueBaby => "bluebaby",
        PetAppearanceID.Eve => "eve",
        PetAppearanceID.Samson => "samson",
        PetAppearanceID.Azazel => "azazel",
        PetAppearanceID.Lazarus => "lazarus",
        PetAppearanceID.Eden => "eden",
        PetAppearanceID.TheLost => "thelost",
        PetAppearanceID.Lilith => "lilith",
        PetAppearanceID.Keeper => "keeper",
        PetAppearanceID.Apollyon => "apollyon",
        PetAppearanceID.TheForgotten => "theforgotten",
        PetAppearanceID.Bethany => "bethany",
        PetAppearanceID.JacobEsau => "jacobesau",
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
